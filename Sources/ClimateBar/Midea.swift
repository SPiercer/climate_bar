import CommonCrypto
import CryptoKit
import Foundation
import Network
import os

// Midea V3 LAN protocol (TCP 6444), ported from midea-local (github.com/midea-lan/midea-local).
//
// Layers, outside in:
//   8370 frame  – handshake, then AES-CBC with the session key + SHA-256 sign
//   5A5A packet – AES-ECB with a fixed LAN key + MD5 sign, carries the device ID
//   AA frame    – the AC command/status itself, with a CRC8 and a sum checksum

struct ACStatus: Equatable, Sendable {
  var power = false
  var mode: UInt8 = 2  // 1 auto, 2 cool, 3 dry, 4 heat, 5 fan
  var target = 24.0
  var fanRaw: UInt8 = 102
  var indoor: Double?
  // Sent back unchanged on every set: the AC has no partial update, only "here is the whole state".
  var swingVertical = false, swingHorizontal = false, boost = false, powerSaving = false
  var smartEye = false, dry = false, auxHeating = false, eco = false, anion = false
  var fahrenheit = false, sleep = false, naturalWind = false, frostProtect = false, comfort = false

  var fan: String {
    get { fanRaw == 102 ? "Auto" : fanRaw >= 80 ? "High" : fanRaw >= 60 ? "Medium" : "Low" }
    set { fanRaw = ["Low": 40, "Medium": 60, "High": 80][newValue] ?? 102 }
  }
}

enum MideaError: Error { case timeout, closed, authFailed, badReply }

struct DeviceConfig: Codable, Sendable {
  let name: String
  let ip: String
  let device_id: UInt64
  let token: String
  let key: String
}

/// One AC. Every call opens a short session (connect, handshake, talk, close): the unit allows a single client at a time.
actor MideaAC {
  let config: DeviceConfig

  init(_ config: DeviceConfig) { self.config = config }

  func status() async throws -> ACStatus {
    let session = try await Session.open(config)
    defer { session.close() }
    try await session.send(frame: Frame.query())
    return try await session.readStatus()
  }

  /// Reads the current state, applies the change and sends the whole state back.
  func update(_ change: @Sendable (inout ACStatus) -> Void) async throws -> ACStatus {
    let session = try await Session.open(config)
    defer { session.close() }
    try await session.send(frame: Frame.query())
    var state = try await session.readStatus()
    change(&state)
    try await session.send(frame: Frame.set(state, version: session.protocolVersion))
    return try await session.readStatus()
  }
}

// MARK: - Session (8370 + 5A5A layers)

private final class Session: @unchecked Sendable {
  private let conn: NWConnection
  private let queue = DispatchQueue(label: "midea.session")
  private let deviceID: UInt64
  private var tcpKey: [UInt8] = []
  private var requestCount: UInt16 = 0
  private var buffer: [UInt8] = []
  private(set) var protocolVersion: UInt8 = 0

  private init(_ config: DeviceConfig) {
    conn = NWConnection(host: .init(config.ip), port: 6444, using: .tcp)
    deviceID = config.device_id
  }

  static func open(_ config: DeviceConfig) async throws -> Session {
    let session = Session(config)
    try await session.start()
    try await session.handshake(token: [UInt8](hex: config.token), key: [UInt8](hex: config.key))
    return session
  }

  func close() { conn.cancel() }

  private func start() async throws {
    let _: Void = try await wait { done in
      conn.stateUpdateHandler = { state in
        switch state {
        case .ready: done(.success(()))
        case .failed(let error), .waiting(let error): done(.failure(error))
        default: break
        }
      }
      conn.start(queue: queue)
    }
  }

  private func handshake(token: [UInt8], key: [UInt8]) async throws {
    try await write(encode8370(token, type: 0x0))
    let reply = try await read()
    guard reply.count >= 72 else { throw MideaError.authFailed }
    let payload = Array(reply[8..<40]), sign = Array(reply[40..<72])
    let plain = Crypto.aes(CCOperation(kCCDecrypt), payload, key: key, iv: Crypto.zeroIV, pad: false)
    guard Crypto.sha256(plain) == sign else { throw MideaError.authFailed }
    tcpKey = zip(plain, key).map { $0 ^ $1 }
    requestCount = 0
  }

  func send(frame: [UInt8]) async throws {
    try await write(encode8370(Packet.wrap(frame, deviceID: deviceID), type: 0x6))
  }

  /// Reads until a C0 status reply arrives, skipping heartbeats and other notifications.
  func readStatus() async throws -> ACStatus {
    while true {
      buffer += try await read()
      for packet in try decode8370() {
        guard let frame = Packet.unwrap(packet) else { continue }
        if let status = Frame.parseStatus(frame) {
          protocolVersion = frame[8]
          return status
        }
      }
    }
  }

  private func encode8370(_ payload: [UInt8], type: UInt8) -> [UInt8] {
    var data = payload, size = payload.count, padding = 0
    let encrypted = type == 0x6
    if encrypted && (size + 2) % 16 != 0 {
      padding = 16 - ((size + 2) & 0xF)
      size += padding + 32
      data += (0..<padding).map { _ in UInt8.random(in: 0...255) }
    }
    let header: [UInt8] = [0x83, 0x70, UInt8(size >> 8), UInt8(size & 0xFF), 0x20, UInt8(padding << 4) | type]
    data = [UInt8(requestCount >> 8), UInt8(requestCount & 0xFF)] + data
    requestCount &+= 1
    if encrypted {
      let sign = Crypto.sha256(header + data)
      data = Crypto.aes(CCOperation(kCCEncrypt), data, key: tcpKey, iv: Crypto.zeroIV, pad: false) + sign
    }
    return header + data
  }

  private func decode8370() throws -> [[UInt8]] {
    var packets: [[UInt8]] = []
    while buffer.count >= 6 {
      let header = Array(buffer[0..<6])
      guard header[0] == 0x83, header[1] == 0x70, header[4] == 0x20 else { throw MideaError.badReply }
      let size = (Int(header[2]) << 8 | Int(header[3])) + 8
      guard buffer.count >= size else { break }
      var body = Array(buffer[6..<size])
      buffer.removeFirst(size)
      let padding = Int(header[5] >> 4), type = header[5] & 0xF
      if type == 0x3 || type == 0x6 {
        let sign = Array(body.suffix(32))
        body = Crypto.aes(CCOperation(kCCDecrypt), Array(body.dropLast(32)), key: tcpKey, iv: Crypto.zeroIV, pad: false)
        guard Crypto.sha256(header + body) == sign else { throw MideaError.badReply }
        body.removeLast(padding)
      }
      packets.append(Array(body.dropFirst(2)))  // request counter
    }
    return packets
  }

  private func write(_ bytes: [UInt8]) async throws {
    let _: Void = try await wait { done in
      conn.send(content: Data(bytes), completion: .contentProcessed { error in
        done(error.map { .failure($0) } ?? .success(()))
      })
    }
  }

  private func read() async throws -> [UInt8] {
    try await wait { done in
      conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
        if let error { done(.failure(error)) } else if let data, !data.isEmpty { done(.success([UInt8](data))) } else {
          done(.failure(MideaError.closed))
        }
      }
    }
  }

  /// Bridges a callback to async, failing with `.timeout` after `seconds`.
  private func wait<T: Sendable>(
    _ seconds: Double = 5, _ start: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      let finished = OSAllocatedUnfairLock(initialState: false)
      let done: @Sendable (Result<T, Error>) -> Void = { result in
        let first = finished.withLock { wasDone in
          defer { wasDone = true }
          return !wasDone
        }
        if first { continuation.resume(with: result) }
      }
      queue.asyncAfter(deadline: .now() + seconds) { done(.failure(MideaError.timeout)) }
      start(done)
    }
  }
}

// MARK: - 5A5A packet

private enum Packet {
  static func wrap(_ frame: [UInt8], deviceID: UInt64) -> [UInt8] {
    var packet: [UInt8] = [0x5A, 0x5A, 0x01, 0x11, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00]
    packet += time()
    packet += (0..<8).map { UInt8(truncatingIfNeeded: deviceID >> (8 * $0)) }  // little-endian
    packet += [UInt8](repeating: 0, count: 12)
    packet += Crypto.aes(CCOperation(kCCEncrypt), frame, key: Crypto.lanKey, iv: nil, pad: true)
    let length = packet.count + 16
    packet[4] = UInt8(length & 0xFF)
    packet[5] = UInt8(length >> 8)
    return packet + Crypto.md5(packet + Crypto.salt)
  }

  /// The AA frame inside a 5A5A packet, or nil for heartbeats / errors.
  static func unwrap(_ packet: [UInt8]) -> [UInt8]? {
    guard packet.count > 56, packet != Array("ERROR".utf8) else { return nil }
    let type = Int(packet[2]) | Int(packet[3]) << 8
    guard type != 0x1001, type != 0x0001 else { return nil }
    let frame = Crypto.aes(CCOperation(kCCDecrypt), Array(packet[40..<(packet.count - 16)]), key: Crypto.lanKey, iv: nil, pad: true)
    return frame.first == 0xAA ? frame : nil
  }

  /// UTC yyyyMMddHHmmssSS as two-digit numbers, last first.
  private static func time() -> [UInt8] {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMddHHmmssSS"
    let digits = Array(formatter.string(from: .now))
    return stride(from: 0, to: 16, by: 2).map { UInt8(String(digits[$0...$0 + 1]))! }.reversed()
  }
}

// MARK: - AA frame (AC commands)

enum Frame {
  nonisolated(unsafe) private static var messageID: UInt8 = 0

  static func query() -> [UInt8] {
    frame(type: 0x03, body: body(0x41, [0x81, 0x00, 0xFF] + [UInt8](repeating: 0, count: 16)), version: 0)
  }

  static func set(_ s: ACStatus, version: UInt8) -> [UInt8] {
    let target = UInt8(Int(s.target) & 0xF) | (Int(s.target * 2) % 2 != 0 ? 0x10 : 0)
    let payload: [UInt8] = [
      (s.power ? 0x01 : 0) | 0x40,  // 0x40 = beep
      (s.mode << 5) & 0xE0 | target,
      s.fanRaw & 0x7F,
      0, 0, 0,
      0x30 | (s.swingVertical ? 0x0C : 0) | (s.swingHorizontal ? 0x03 : 0),
      (s.boost ? 0x20 : 0) | (s.powerSaving ? 0x08 : 0),
      (s.smartEye ? 0x01 : 0) | (s.dry ? 0x04 : 0) | (s.auxHeating ? 0x08 : 0) | (s.eco ? 0x80 : 0) | (s.anion ? 0x20 : 0),
      (s.fahrenheit ? 0x04 : 0) | (s.sleep ? 0x01 : 0) | (s.boost ? 0x02 : 0),
      0, 0, 0, 0, 0, 0,
      s.naturalWind ? 0x40 : 0,
      0, 0, 0,
      s.frostProtect ? 0x80 : 0,
      s.comfort ? 0x01 : 0,
    ]
    return frame(type: 0x02, body: body(0x40, payload), version: version)
  }

  /// Decodes a C0 status reply (a query or set answer).
  static func parseStatus(_ frame: [UInt8]) -> ACStatus? {
    guard frame.count > 33, frame[0] == 0xAA, frame[10] == 0xC0 else { return nil }
    let b = Array(frame[10..<(frame.count - 1)])
    func bit(_ i: Int, _ mask: UInt8) -> Bool { i < b.count && b[i] & mask != 0 }
    var s = ACStatus()
    s.power = bit(1, 0x01)
    s.mode = (b[2] & 0xE0) >> 5
    s.target = Double(b[2] & 0x0F) + 16 + (bit(2, 0x10) ? 0.5 : 0)
    s.fanRaw = b[3] & 0x7F
    s.swingVertical = bit(7, 0x0C)
    s.swingHorizontal = bit(7, 0x03)
    s.boost = bit(8, 0x20) || bit(10, 0x02)
    s.powerSaving = bit(8, 0x08)
    s.smartEye = bit(8, 0x40)
    s.naturalWind = bit(9, 0x02)
    s.dry = bit(9, 0x04)
    s.auxHeating = bit(9, 0x08)
    s.eco = bit(9, 0x10)
    s.anion = bit(9, 0x20)
    s.fahrenheit = bit(10, 0x04)
    s.sleep = bit(10, 0x01)
    s.frostProtect = bit(21, 0x80)
    s.comfort = bit(22, 0x01)
    s.indoor = temperature(b[11], decimal: b.count > 20 ? b[15] & 0x0F : 0)
    return s
  }

  private static func temperature(_ raw: UInt8, decimal: UInt8) -> Double? {
    guard raw != 0xFF else { return nil }
    let whole = (Double(raw) - 50) / 2
    guard decimal != 0 else { return whole }
    return whole < 0 ? Double(Int(whole)) - Double(decimal) * 0.1 : Double(Int(whole)) + Double(decimal) * 0.1
  }

  /// Body type + payload + message ID + CRC8.
  private static func body(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
    messageID = messageID >= 253 ? 1 : messageID + 1
    let body = [type] + payload + [messageID]
    return body + [crc8(body)]
  }

  private static func frame(type: UInt8, body: [UInt8], version: UInt8) -> [UInt8] {
    let frame: [UInt8] = [0xAA, UInt8(10 + body.count), 0xAC, 0, 0, 0, 0, 0, version, type] + body
    return frame + [checksum(frame)]
  }

  static func checksum(_ frame: [UInt8]) -> UInt8 {
    UInt8((256 - frame.dropFirst().reduce(0) { $0 + Int($1) } % 256) % 256)
  }

  /// Dallas/Maxim CRC-8 (midea-local's crc8_854_table).
  static func crc8(_ bytes: [UInt8]) -> UInt8 {
    var crc: UInt8 = 0
    for byte in bytes {
      crc ^= byte
      for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0x8C : crc >> 1 }
    }
    return crc
  }
}

// MARK: - Crypto

private enum Crypto {
  static let lanKey = [UInt8](hex: "6a92ef406bad2f0359baad994171ea6d")
  static let salt = [UInt8](hex: "78686469776a6e6368656b6434643531326368646a783564386534633339344432443753")
  static let zeroIV = [UInt8](repeating: 0, count: 16)

  /// AES: CBC when `iv` is given, ECB otherwise.
  static func aes(_ op: CCOperation, _ data: [UInt8], key: [UInt8], iv: [UInt8]?, pad: Bool) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: data.count + 16)
    var moved = 0
    let options = CCOptions((iv == nil ? kCCOptionECBMode : 0) | (pad ? kCCOptionPKCS7Padding : 0))
    let status = CCCrypt(
      op, CCAlgorithm(kCCAlgorithmAES), options, key, key.count, iv, data, data.count,
      &out, out.count, &moved)
    return status == kCCSuccess ? Array(out[0..<moved]) : []
  }

  static func sha256(_ data: [UInt8]) -> [UInt8] { Array(SHA256.hash(data: data)) }
  static func md5(_ data: [UInt8]) -> [UInt8] { Array(Insecure.MD5.hash(data: data)) }
}

extension [UInt8] {
  init(hex: String) {
    let chars = Array(hex.utf8)
    self = stride(from: 0, to: chars.count - 1, by: 2).map {
      UInt8(String(decoding: chars[$0...$0 + 1], as: UTF8.self), radix: 16) ?? 0
    }
  }
}
