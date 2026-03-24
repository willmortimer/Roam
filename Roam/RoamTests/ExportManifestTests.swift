import Testing
import Foundation
@testable import Roam

@Suite("ExportManifest Codable")
struct ExportManifestTests {
    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    let decoder = JSONDecoder()

    @Test("ExportedHost round-trip encoding")
    func hostRoundTrip() throws {
        let host = ExportedHost(
            id: "host_abc123",
            alias: "dev-server",
            hostname: "192.168.1.10",
            port: 22,
            username: "deploy",
            authMethod: "key",
            keyReference: "key_xyz",
            jumpChain: ["bastion_1"],
            tags: ["dev", "gpu"],
            folder: "ml-cluster",
            notes: "Main dev box",
            environment: "dev",
            trustClass: "trustedDev"
        )

        let data = try encoder.encode(host)
        let decoded = try decoder.decode(ExportedHost.self, from: data)

        #expect(decoded.id == host.id)
        #expect(decoded.alias == host.alias)
        #expect(decoded.hostname == host.hostname)
        #expect(decoded.port == host.port)
        #expect(decoded.username == host.username)
        #expect(decoded.authMethod == host.authMethod)
        #expect(decoded.keyReference == host.keyReference)
        #expect(decoded.jumpChain == host.jumpChain)
        #expect(decoded.tags == host.tags)
        #expect(decoded.folder == host.folder)
        #expect(decoded.notes == host.notes)
    }

    @Test("Full manifest round-trip")
    func fullManifestRoundTrip() throws {
        let manifest = ExportManifest(
            version: 1,
            exported_at: "2026-03-23T12:00:00Z",
            hosts: [
                ExportedHost(
                    id: "h1", alias: "test", hostname: "test.com", port: 22,
                    username: "root", authMethod: "key", keyReference: nil,
                    jumpChain: [], tags: [], folder: nil, notes: "",
                    environment: "dev", trustClass: "trustedDev"
                )
            ],
            workspaces: [],
            snippets: [],
            keys: nil
        )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(ExportManifest.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.hosts.count == 1)
        #expect(decoded.hosts[0].alias == "test")
        #expect(decoded.workspaces.isEmpty)
        #expect(decoded.snippets.isEmpty)
        #expect(decoded.keys == nil)
    }

    @Test("Manifest with keys round-trips")
    func manifestWithKeys() throws {
        let manifest = ExportManifest(
            version: 1,
            exported_at: "2026-03-23T12:00:00Z",
            hosts: [],
            workspaces: [],
            snippets: [],
            keys: [ExportedKey(id: "k1", data: "base64encodedkey==")]
        )

        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(ExportManifest.self, from: data)

        #expect(decoded.keys?.count == 1)
        #expect(decoded.keys?[0].id == "k1")
    }
}
