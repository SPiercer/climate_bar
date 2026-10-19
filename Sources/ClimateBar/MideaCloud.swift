import CryptoKit
import Foundation
import Network

// Midea "SmartHome" (MSmartHome overseas) cloud, ported from midea-local's
// cloud.py / security.py — only what onboarding needs: log in, then fetch each
// AC's LAN token/key with getToken. The device IP comes from LAN discovery
// (the cloud doesn't report it), so the session-AES and appliance-list paths
// midea-local uses elsewhere are not needed here.

struct CloudError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

// MARK: - Cloud crypto (SmartHome constants are compile-time public values)

private enum CloudCrypto {
  static let appID = "1010"
  static let appKey = "ac21b9f9cbfe4ca5a88562ef25e2b768"  // == login_key
  static let iotKey = "meicloud"
  static let hmacKey = "PROD_VnoClJI9aikS8dyy"
  static let apiURL = "https://mp-prod.appsmb.com/mas/v5/app/proxy?alias="

  static func sha256Hex(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static func md5Hex(_ s: String) -> String {
    Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// hex(hmac_sha256(hmac_key, iot_key + body + random)) — the `sign` header.
  static func sign(body: String, random: String) -> String {
    let msg = Data((iotKey + body + random).utf8)
    let mac = HMAC<SHA256>.authenticationCode(for: msg, using: .init(data: Data(hmacKey.utf8)))
    return mac.map { String(format: "%02x", $0) }.joined()
  }

  static func deviceID(_ account: String) -> String {
    String(sha256Hex("Hello, \(account)!").prefix(16))
  }

  /// Two UDP-id encodings the AC may key its token under (big / little, 6 bytes).
  static func udpID(_ applianceID: UInt64, method: Int) -> String {
    let bytes: [UInt8]
    if method == 1 {  // BIG, 6 bytes
      bytes = (0..<6).reversed().map { UInt8(truncatingIfNeeded: applianceID >> (8 * $0)) }
    } else {  // LITTLE, 6 bytes
      bytes = (0..<6).map { UInt8(truncatingIfNeeded: applianceID >> (8 * $0)) }
    }
    var d = Array(SHA256.hash(data: Data(bytes)))
    for i in 0..<16 { d[i] ^= d[i + 16] }
    return d[0..<16].map { String(format: "%02x", $0) }.joined()
  }

  static func encryptPassword(loginID: String, password: String) -> String {
    sha256Hex(loginID + sha256Hex(password) + appKey)
  }

  static func encryptIamPassword(loginID: String, password: String) -> String {
    sha256Hex(loginID + md5Hex(md5Hex(password)) + appKey)
  }

  static let authBasic = Data("\(appKey):\(iotKey)".utf8).base64EncodedString()
}

// MARK: - Cloud client

final class MideaCloudClient {
  struct CloudKey { let token: String, key: String }

  private let account: String
  private let password: String
  private let session = URLSession(configuration: .ephemeral)
  private var apiURL = CloudCrypto.apiURL
  private let deviceID: String
  private var uid: String?
  private var accessToken: String?
  private var loginID = ""

  init(account: String, password: String) {
    self.account = account
    self.password = password
    deviceID = CloudCrypto.deviceID(account)
  }

  private func generalData() -> [String: Any] {
    [
      "src": CloudCrypto.appID, "format": "2",
      "stamp": Self.stamp(), "platformId": "1", "deviceId": deviceID,
      "reqId": Self.randomHex(16), "uid": uid ?? NSNull(),
      "clientType": "1", "appId": CloudCrypto.appID, "language": "en_US",
    ]
  }

  /// One signed POST; returns the response's `data` object or throws the cloud's message.
  private func request(_ endpoint: String, _ data: [String: Any]) async throws -> [String: Any] {
    let body = try JSONSerialization.data(withJSONObject: data)
    let bodyString = String(decoding: body, as: UTF8.self)
    let random = String(Int(Date().timeIntervalSince1970))

    var req = URLRequest(url: URL(string: apiURL + endpoint)!)
    req.httpMethod = "POST"
    req.httpBody = body
    req.timeoutInterval = 10
    req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
    req.setValue("1", forHTTPHeaderField: "secretVersion")
    req.setValue(CloudCrypto.sign(body: bodyString, random: random), forHTTPHeaderField: "sign")
    req.setValue(random, forHTTPHeaderField: "random")
    req.setValue(CloudCrypto.appID, forHTTPHeaderField: "x-recipe-app")
    req.setValue("Basic \(CloudCrypto.authBasic)", forHTTPHeaderField: "authorization")
    uid.map { req.setValue($0, forHTTPHeaderField: "uid") }
    accessToken.map { req.setValue($0, forHTTPHeaderField: "accessToken") }

    let (respData, _) = try await session.data(for: req)
    guard let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
      throw CloudError("Unexpected cloud response.")
    }
    let code = (json["code"] as? Int) ?? Int("\(json["code"] ?? "")") ?? -1
    if code == 0, let payload = json["data"] as? [String: Any] { return payload }
    throw CloudError("Cloud error \(code): \(json["msg"] ?? "unknown")")
  }

  /// Point at the account's home region. ponytail: endpoint-2 (plaintext) only;
  /// the AES-signed endpoint-1 is skipped, add it if a region rejects login.
  private func reroute() async {
    var data = generalData()
    data["userType"] = "0"
    data["userName"] = account
    if let r = try? await request("/v1/multicloud/platform/user/route", data),
      let url = r["masUrl"] as? String, !url.isEmpty {
      apiURL = url  // masUrl already ends in /mas/v5/app/proxy?alias=
    }
  }

  func login() async throws {
    await reroute()
    var idData = generalData()
    idData["loginAccount"] = account
    let idResp = try await request("/v1/user/login/id/get", idData)
    guard let lid = idResp["loginId"] as? String else { throw CloudError("No loginId returned.") }
    loginID = lid

    let stamp = Self.stamp()
    var iot = generalData()
    iot.removeValue(forKey: "uid")
    iot["iampwd"] = CloudCrypto.encryptIamPassword(loginID: loginID, password: password)
    iot["loginAccount"] = account
    iot["password"] = CloudCrypto.encryptPassword(loginID: loginID, password: password)
    iot["stamp"] = stamp
    let data: [String: Any] = [
      "iotData": iot,
      "data": ["appKey": CloudCrypto.appKey, "deviceId": deviceID, "platform": "2"],
      "stamp": stamp,
    ]
    let resp = try await request("/mj/user/login", data)
    guard let u = resp["uid"] as? String,
      let mdata = resp["mdata"] as? [String: Any],
      let token = mdata["accessToken"] as? String
    else { throw CloudError("Login succeeded but the response was missing a token.") }
    uid = u
    accessToken = token
  }

  /// Candidate token/key pairs for one appliance (one per UDP-id method that matched).
  func token(for applianceID: UInt64) async throws -> [CloudKey] {
    var keys: [CloudKey] = []
    for method in [1, 2] {
      let udp = CloudCrypto.udpID(applianceID, method: method)
      var data = generalData()
      data["udpid"] = udp
      data["applianceCodes"] = String(applianceID)
      let resp = try await request("/v1/iot/secure/getToken", data)
      for entry in (resp["tokenlist"] as? [[String: Any]]) ?? [] {
        if entry["udpId"] as? String == udp,
          let t = entry["token"] as? String, let k = entry["key"] as? String {
          keys.append(CloudKey(token: t.lowercased(), key: k.lowercased()))
        }
      }
    }
    return keys
  }

  private static func stamp() -> String {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyyMMddHHmmss"
    return f.string(from: .now)
  }

  private static func randomHex(_ n: Int) -> String {
    (0..<n).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
  }
}

// MARK: - Crypto self-test (reference values from midea-local)

enum CloudSelfTest {
  static func run() {
    assert(CloudCrypto.deviceID("test@example.com") == "7094742dc19e48a2", "deviceID")
    assert(CloudCrypto.udpID(151732607074707, method: 1) == "f67c74399f0c1a6bb44bb49b5d8e850c", "udp1")
    assert(CloudCrypto.udpID(151732607074707, method: 2) == "7039b258ee6a9983e17fbcf6d0458d09", "udp2")
    assert(CloudCrypto.sign(body: "{\"a\":1}", random: "1700000000")
      == "b4ec9abc070f98cb7f549acafb8db7ec1c2c076537f153c8e311079eeed30e82", "sign")
    assert(CloudCrypto.encryptPassword(loginID: "abc123LOGINID", password: "hunter2")
      == "1d91173db118c952239fd83ed79cc9b52e43e76a77c59a0302e891fed1c88563", "encpw")
    assert(CloudCrypto.encryptIamPassword(loginID: "abc123LOGINID", password: "hunter2")
      == "09f5a5af5bd0d4d62ec67d77ccf380d5636690d47469b3341330f2770fbb4f6c", "enciam")
  }
}
