import CommonCrypto
import Darwin
import Foundation

// LAN discovery, ported from midea-local's discover.py (V3 / 5A5A path only —
// enough to learn each AC's IP and device id, which the cloud doesn't report).
// Uses a BSD broadcast socket the same way the Python does.

struct DiscoveredAC: Sendable {
  let ip: String
  let deviceID: UInt64
  let port: UInt16
  let protocolVersion: Int
}

enum Discovery {
  private static let broadcastMsg = [UInt8](hex:
    "5a5a01114800920000000000000000000000000000000000000000000000000000000000000000"
    + "007f75bd6b3e4f8b762e849c6e578d6590036e9d4342a50f1f569eb8ec918e92e5")
  private static let lanKey = [UInt8](hex: "6a92ef406bad2f0359baad994171ea6d")

  /// Broadcast and collect replies for `timeout` seconds.
  static func scan(timeout: TimeInterval = 4) -> [DiscoveredAC] {
    let sock = socket(AF_INET, SOCK_DGRAM, 0)
    guard sock >= 0 else { return [] }
    defer { close(sock) }
    var on: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    // Subnet-directed broadcasts (192.168.1.255 etc.) reach ACs that routers/APs
    // drop the global 255.255.255.255 to; keep the global one as a fallback.
    let targets = broadcastAddrs() + [INADDR_BROADCAST]
    for addr in targets {
      for port in [UInt16(6445), UInt16(20086)] { send(broadcastMsg, to: addr, on: sock, port: port) }
    }

    var found: [UInt64: DiscoveredAC] = [:]
    let deadline = Date().addingTimeInterval(timeout)
    var buf = [UInt8](repeating: 0, count: 512)
    while Date() < deadline {
      var addr = sockaddr_in()
      var len = socklen_t(MemoryLayout<sockaddr_in>.size)
      let n = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
          recvfrom(sock, &buf, buf.count, 0, sa, &len)
        }
      }
      if n <= 0 { continue }  // timeout tick or error
      let ip = String(cString: inet_ntoa(addr.sin_addr))
      if let ac = parse(Array(buf[0..<n]), ip: ip) { found[ac.deviceID] = ac }
    }
    return Array(found.values)
  }

  /// IPv4 subnet broadcast address of every up, non-loopback interface (network byte order).
  private static func broadcastAddrs() -> [in_addr_t] {
    var out: [in_addr_t] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0 else { return out }
    defer { freeifaddrs(ifap) }
    var p = ifap
    while let cur = p {
      defer { p = cur.pointee.ifa_next }
      let flags = Int32(cur.pointee.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
        let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
        let nm = cur.pointee.ifa_netmask else { continue }
      let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
      let mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
      out.append((ip & mask) | ~mask)  // already network byte order
    }
    return out
  }

  private static func send(_ bytes: [UInt8], to target: in_addr_t, on sock: Int32, port: UInt16) {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = target
    _ = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        bytes.withUnsafeBytes { sendto(sock, $0.baseAddress, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) }
      }
    }
  }

  /// One discovery reply -> AC, or nil if it isn't a parseable 5A5A/8370 device.
  private static func parse(_ raw: [UInt8], ip: String) -> DiscoveredAC? {
    guard raw.count >= 104 else { return nil }
    var data = raw
    var proto = 0
    if raw[0] == 0x5A, raw[1] == 0x5A {
      proto = 2
    } else if raw[0] == 0x83, raw[1] == 0x70, raw[8] == 0x5A, raw[9] == 0x5A {
      proto = 3
      data = Array(raw[8..<(raw.count - 16)])
    } else {
      return nil
    }
    guard data.count >= 56 else { return nil }
    let deviceID = (0..<6).reduce(UInt64(0)) { $0 | UInt64(data[20 + $1]) << (8 * $1) }
    let encrypted = Array(data[40..<(data.count - 16)])
    let reply = aesECBDecrypt(encrypted, key: lanKey)
    guard reply.count > 41, Int(reply[40]) + 41 <= reply.count else { return nil }
    let port = (0..<4).reduce(UInt32(0)) { $0 | UInt32(reply[4 + $1]) << (8 * $1) }
    return DiscoveredAC(ip: ip, deviceID: deviceID, port: UInt16(truncatingIfNeeded: port), protocolVersion: proto)
  }

  private static func aesECBDecrypt(_ data: [UInt8], key: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
    var moved = 0
    let status = CCCrypt(
      CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
      CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
      key, key.count, nil, data, data.count, &out, out.count, &moved)
    return status == kCCSuccess ? Array(out[0..<moved]) : []
  }
}
