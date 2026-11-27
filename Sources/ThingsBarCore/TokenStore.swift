import Foundation
import Security

/// Stores the Things URL auth token. The live app uses the Keychain.
public protocol TokenStoring: AnyObject, Sendable {
    var token: String? { get }
    func setToken(_ token: String?) throws
}

/// Generic-password Keychain item, cached in memory after the first read.
public final class KeychainTokenStore: TokenStoring, @unchecked Sendable {
    private let service: String
    private let account = "things-auth-token"
    private let lock = NSLock()
    private var cached: String??

    public init(service: String = "local.thingsbar.ThingsBar") { self.service = service }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public var token: String? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let value: String? = SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess
            ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        cached = .some(value)
        return value
    }

    public func setToken(_ token: String?) throws {
        lock.lock(); defer { lock.unlock() }
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        if let trimmed, !trimmed.isEmpty {
            var item = baseQuery
            item[kSecValueData as String] = Data(trimmed.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            cached = .some(trimmed)
        } else {
            cached = .some(nil)
        }
    }
}

/// In-memory token store for tests and self-tests.
public final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    public init(_ value: String? = nil) { self.value = value }
    public var token: String? { lock.withLock { value } }
    public func setToken(_ token: String?) throws {
        lock.withLock { value = token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
