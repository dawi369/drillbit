import Foundation
import Security

nonisolated enum SharedStore {
  static let group = "group.dawi.drillbit"
  static let widgetKind = "DrillbitWidget"
  static var snapshotURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("widget.json")
  }
  static func snapshot() -> WidgetSnapshot? {
    guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder.api.decode(WidgetSnapshot.self, from: data)
  }
  static func save(_ snapshot: WidgetSnapshot) throws {
    guard let url = snapshotURL else { return }
    let minimal = WidgetSnapshot(
      challenge: snapshot.challenge?.widgetSummary, updatedAt: snapshot.updatedAt)
    try JSONEncoder().encode(minimal).write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  static func setSecret(_ value: String?, key: String) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: group,
      kSecAttrAccount as String: key,
    ]
    if let access = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String,
      !access.contains("$(")
    {
      query[kSecAttrAccessGroup as String] = access
    }
    SecItemDelete(query as CFDictionary)
    guard let value else { return }
    query[kSecValueData as String] = Data(value.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let result = SecItemAdd(query as CFDictionary, nil)
    guard result == errSecSuccess else {
      throw APIError(code: "keychain", message: "Secure storage is unavailable.", status: 0)
    }
  }
  static func secret(_ key: String) -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: group,
      kSecAttrAccount as String: key, kSecReturnData as String: true,
    ]
    if let access = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String,
      !access.contains("$(")
    {
      query[kSecAttrAccessGroup as String] = access
    }
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
