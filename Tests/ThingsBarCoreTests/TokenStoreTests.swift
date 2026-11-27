import Foundation
import Testing
@testable import ThingsBarCore

struct TokenStoreTests {
    @Test func memoryStoreTrimsAndClears() throws {
        let s = MemoryTokenStore()
        try s.setToken("  abc \n")
        #expect(s.token == "abc")
        try s.setToken("")
        #expect(s.token == nil)
    }

    /// Uses a throwaway Keychain service name and removes it afterwards.
    @Test func keychainRoundTrip() throws {
        let service = "local.thingsbar.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service)
        defer { try? store.setToken(nil) }
        #expect(store.token == nil)
        try store.setToken("secret-1")
        #expect(KeychainTokenStore(service: service).token == "secret-1", "persists across instances")
        try store.setToken("secret-2")
        #expect(KeychainTokenStore(service: service).token == "secret-2", "overwrites")
        try store.setToken(nil)
        #expect(KeychainTokenStore(service: service).token == nil, "deletes")
    }
}
