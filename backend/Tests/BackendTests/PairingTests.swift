//
//  PairingTests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

@testable import Backend
import Foundation
import Shared
import Synchronization
import Testing
import VaporTesting

@Suite("Connection pairing")
struct PairingTests {
    @Test("Unapproved credentials and visible codes cannot access account routes")
    func approvalRequired() async throws {
        try await withPairing { app, _, directory in
            let credential = PairingStore.secret()
            let attempt = try await start(app, credential: credential)
            #expect(!attempt.approved)
            for token in [credential, attempt.id, attempt.code] {
                try await app.testing().test(.GET, "session", headers: ["Authorization": "Bearer \(token)"], afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            }
            try await app.testing().test(.GET, "pairing/\(attempt.id)", headers: ["Authorization": "Bearer wrong"], afterResponse: { res async in
                #expect(res.status == .notFound)
            })
            try PairingStore.approve(code: attempt.code, directory: directory)
            try await app.testing().test(.GET, "pairing/\(attempt.id)", headers: ["Authorization": "Bearer \(credential)"], afterResponse: { res async throws in
                #expect(res.status == .ok)
                #expect(try res.content.decode(PairingStatus.self).approved)
                #expect(!res.body.string.contains(credential))
            })
            try await app.testing().test(.GET, "session", headers: ["Authorization": "Bearer \(credential)"], afterResponse: { res async in
                #expect(res.status == .ok)
            })
            let reopened = try PairingStore(directory: directory)
            #expect(await reopened.accepts(credential))
            #expect(try !String(contentsOf: directory.appendingPathComponent("installation.json"), encoding: .utf8).contains(credential))
        }
    }

    @Test("Only a Keychain bootstrap proof permits automatic approval")
    func localProof() async throws {
        try await withPairing { app, store, _ in
            let credential = PairingStore.secret()
            let untrusted = try await start(app, credential: PairingStore.secret(), proof: "wrong")
            #expect(!untrusted.approved)
            let attempt = try await start(app, credential: credential, proof: store.localSecret())
            #expect(attempt.approved)
            #expect(await store.accepts(credential))
            try await app.testing().test(.DELETE, "pairing/\(attempt.id)", headers: ["Authorization": "Bearer \(credential)"], afterResponse: { res async in
                #expect(res.status == .noContent)
            })
            #expect(await !(store.accepts(credential)))
            try await app.testing().test(.GET, "pairing/\(attempt.id)", headers: ["Authorization": "Bearer \(credential)"], afterResponse: { res async in
                #expect(res.status == .notFound)
            })
        }
    }

    @Test("Expired attempts cannot receive approval, and unapproved request counts are bounded")
    func expiryAndCapacity() async throws {
        try await withPairing { app, _, directory in
            let credential = PairingStore.secret()
            let attempt = try await start(app, credential: credential)
            #expect(throws: (any Error).self) {
                try PairingStore.approve(code: attempt.code, directory: directory, now: Date().addingTimeInterval(301))
            }
            for _ in 0 ..< 31 {
                _ = try await start(app, credential: PairingStore.secret())
            }
            try await app.testing().test(.POST, "pairing", beforeRequest: { req in
                try req.content.encode(PairingRequest(credential: PairingStore.secret()), as: .json)
            }, afterResponse: { res async in
                #expect(res.status == .tooManyRequests)
            })
        }
    }

    @Test("Approval cannot revive an expired attempt")
    func expiredPoll() async throws {
        let clock = Mutex(Date())
        try await withPairing(now: { clock.withLock { $0 } }) { app, store, directory in
            let credential = PairingStore.secret()
            let attempt = try await start(app, credential: credential)
            try PairingStore.approve(code: attempt.code, directory: directory)
            clock.withLock { $0 = $0.addingTimeInterval(301) }
            try await app.testing().test(.GET, "pairing/\(attempt.id)", headers: ["Authorization": "Bearer \(credential)"], afterResponse: { res async in
                #expect(res.status == .notFound)
            })
            #expect(await !(store.accepts(credential)))
        }
    }

    private func start(_ app: Application, credential: String, proof: String? = nil) async throws -> PairingStatus {
        let response = try await app.testing().sendRequest(.POST, "pairing", beforeRequest: { req in
            try req.content.encode(PairingRequest(credential: credential), as: .json)
            if let proof {
                req.headers.replaceOrAdd(name: "X-Unaru-Local-Pairing", value: proof)
            }
        })
        #expect(response.status == .ok)
        #expect(response.headers["Cache-Control"] == ["no-store"])
        return try response.content.decode(PairingStatus.self)
    }

    private func withPairing(now: @escaping @Sendable () -> Date = { Date() }, _ test: (Application, PairingStore, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PairingStore(directory: directory, now: now)
        try await withApp(configure: { app in
            try routes(app, connectionToken: nil, pairing: store)
        }) { app in try await test(app, store, directory) }
    }
}
