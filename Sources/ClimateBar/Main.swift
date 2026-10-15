import Foundation

/// Menu bar app by default; `--selftest` and `--status` are command-line checks.
@main
enum Main {
  static func main() {
    switch CommandLine.arguments.dropFirst().first {
    case "--selftest":
      selfTest()
      exit(0)
    case "--discover":
      for ac in Discovery.scan() {
        print("found \(ac.ip)  id=\(ac.deviceID)  port=\(ac.port)  v\(ac.protocolVersion)")
      }
      exit(0)
    case "--status":
      Task {
        await printStatus()
        exit(0)
      }
      dispatchMain()
    default:
      ClimateBarApp.main()
    }
  }

  /// Decodes a status reply captured from the office AC (off, cool, 24°, fan auto, 27.4° indoors).
  static func selfTest() {
    let frame = [UInt8](hex: "aa28ac00000000000803c00048667f7f000000000068ff0c0004000000000000000100000000015fdd")
    assert(Frame.checksum(Array(frame.dropLast())) == frame.last, "checksum")
    assert(Frame.crc8(Array(frame[10..<39])) == frame[39], "crc8")
    let s = Frame.parseStatus(frame)!
    assert(!s.power && s.mode == 2 && s.target == 24 && s.fan == "Auto" && s.indoor == 27.4, "\(s)")
    let set = Frame.set(s, version: 8)
    assert(Frame.checksum(Array(set.dropLast())) == set.last && Frame.crc8(Array(set[10..<(set.count - 2)])) == set[set.count - 2])
    CloudSelfTest.run()
    print("selftest ok")
  }

  static func printStatus() async {
    do {
      for device in try Devices.load() {
        do {
          let s = try await MideaAC(device).status()
          print("\(device.name) (\(device.ip)): power=\(s.power) mode=\(s.mode) target=\(s.target) fan=\(s.fan) indoor=\(s.indoor.map { "\($0)" } ?? "-")")
        } catch {
          print("\(device.name) (\(device.ip)): \(error)")
        }
      }
    } catch {
      print("Can't read \(Devices.url.path): \(error)")
    }
  }
}

/// Per-AC IP, ID, token and key. Lives outside the repo because the token and key are secrets.
enum Devices {
  static let url = URL.applicationSupportDirectory.appending(path: "ClimateBar/devices.json")

  static func load() throws -> [DeviceConfig] {
    try JSONDecoder().decode([DeviceConfig].self, from: Data(contentsOf: url))
  }

  /// Writes the onboarding result where `load()` reads it, 0600 (token/key are secrets).
  static func save(_ configs: [DeviceConfig]) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(configs)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
