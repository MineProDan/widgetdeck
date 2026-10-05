import CoreKit
import Foundation
import Testing

/// Exercises the real Keychain (SecItem) inside the app host.
@Suite("Keychain (real SecItem)", .serialized)
struct KeychainIntegrationTests {
    let keychain = KeychainStore(service: "techflow.tests.\(UUID().uuidString)", accessGroup: nil)

    @Test func crudRoundTrip() throws {
        defer { try? keychain.deleteAll() }
        #expect(try keychain.string(for: "token") == nil)
        try keychain.setString("abc", for: "token")
        #expect(try keychain.string(for: "token") == "abc")
        try keychain.setString("def", for: "token")
        #expect(try keychain.string(for: "token") == "def")
        try keychain.delete("token")
        #expect(try keychain.string(for: "token") == nil)
    }

    @Test func deleteAllRemovesEveryItemInService() throws {
        try keychain.setString("1", for: "a")
        try keychain.setString("2", for: "b")
        try keychain.deleteAll()
        #expect(try keychain.data(for: "a") == nil)
        #expect(try keychain.data(for: "b") == nil)
    }
}
