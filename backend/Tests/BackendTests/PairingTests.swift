//
//  PairingTests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

@testable import Backend
import Crypto
import Foundation
import Shared
import Synchronization
import Testing
import VaporTesting

@Suite("Connection pairing")
struct PairingTests {
    @Test("Only owner-approved public keys can access account routes, and approval survives restart")
    func approvalRequired() async throws {
        try await withPairing { app, _, directory in
            let key = Curve25519.Signing.PrivateKey()
            let attempt = try await start(app, key: key)
            #expect(!attempt.approved)
            let denied = try await app.testing().sendRequest(.GET, "session", beforeRequest: { req in try sign(&req, key: key) })
            #expect(denied.status == .unauthorized)
            try await app.testing().test(.GET, "session", headers: ["Authorization": "Bearer \(attempt.code)"], afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
            let unrelated = try await app.testing().sendRequest(.GET, "pairing/\(attempt.id)", beforeRequest: { req in try sign(&req, key: Curve25519.Signing.PrivateKey()) })
            #expect(unrelated.status == .notFound)
            try PairingStore.approve(code: attempt.code, directory: directory)
            let status = try await app.testing().sendRequest(.GET, "pairing/\(attempt.id)", beforeRequest: { req in try sign(&req, key: key) })
            #expect(try status.content.decode(PairingStatus.self, using: JSONDecoder()).approved)
            let response = try await app.testing().sendRequest(.GET, "session", beforeRequest: { req in try sign(&req, key: key) })
            #expect(response.status == .ok)
            let reopened = try PairingStore(directory: directory)
            #expect(await reopened.contains(publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
            #expect(try !String(contentsOf: directory.appendingPathComponent("installation.json"), encoding: .utf8).contains(key.rawRepresentation.base64EncodedString()))
        }
    }

    @Test("Local proof grants only its bound public key, and cancelling revokes a new offer")
    func localProof() async throws {
        try await withPairing { app, store, _ in
            let key = Curve25519.Signing.PrivateKey()
            let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
            let proof = await proof(store: store, key: key)
            let unrelated = try await start(app, key: Curve25519.Signing.PrivateKey(), proof: proof)
            #expect(!unrelated.approved)
            let attempt = try await start(app, key: key, proof: proof)
            #expect(attempt.approved)
            let response = try await app.testing().sendRequest(.DELETE, "pairing/\(attempt.id)", beforeRequest: { req in try sign(&req, key: key) })
            #expect(response.status == .noContent)
            #expect(await !(store.contains(publicKey: publicKey)))
        }
    }

    @Test("Replaying a captured public key and local proof cannot authorize an attacker request")
    func proofAndRequestReplay() async throws {
        try await withPairing { app, store, _ in
            let owner = Curve25519.Signing.PrivateKey()
            let attacker = Curve25519.Signing.PrivateKey()
            let proof = await proof(store: store, key: owner)
            let response = try await app.testing().sendRequest(.POST, "pairing", beforeRequest: { req in
                try req.content.encode(PairingRequest(publicKey: owner.publicKey.rawRepresentation.base64EncodedString()), as: .json)
                req.headers.replaceOrAdd(name: "X-Unaru-Local-Pairing", value: proof)
                try sign(&req, key: attacker)
            })
            #expect(response.status == .unauthorized)
            _ = try await start(app, key: owner, proof: proof)
            var headers = HTTPHeaders()
            let first = try await app.testing().sendRequest(.GET, "session", beforeRequest: { req in
                try sign(&req, key: owner)
                headers = req.headers
            })
            #expect(first.status == .ok)
            let replay = try await app.testing().sendRequest(.GET, "session", headers: headers)
            #expect(replay.status == .unauthorized)
            let changedPath = try await app.testing().sendRequest(.GET, "profile", headers: headers)
            #expect(changedPath.status == .unauthorized)
        }
    }

    @Test("Approval does not make an earlier signed pairing request replayable")
    func replayAcrossApproval() async throws {
        try await withPairing { app, store, _ in
            let key = Curve25519.Signing.PrivateKey()
            let proof = await proof(store: store, key: key)
            var captured: TestingHTTPRequest?
            let first = try await app.testing().sendRequest(.POST, "pairing", beforeRequest: { req in
                try req.content.encode(PairingRequest(publicKey: key.publicKey.rawRepresentation.base64EncodedString()), as: .json)
                req.headers.replaceOrAdd(name: "X-Unaru-Local-Pairing", value: proof)
                try sign(&req, key: key)
                captured = req
            })
            #expect(first.status == .ok)
            let attempt = try first.content.decode(PairingStatus.self, using: JSONDecoder())
            let replay = try await app.testing().sendRequest(.POST, "pairing", beforeRequest: { req in req = captured! })
            #expect(replay.status == .unauthorized)
            let cancelled = try await app.testing().sendRequest(.DELETE, "pairing/\(attempt.id)", beforeRequest: { req in try sign(&req, key: key) })
            #expect(cancelled.status == .noContent)
            #expect(await !(store.contains(publicKey: key.publicKey.rawRepresentation.base64EncodedString())))
        }
    }

    @Test("Repeated reconnects reuse approval beyond the credential capacity")
    func reconnects() async throws {
        try await withPairing { app, store, _ in
            let key = Curve25519.Signing.PrivateKey()
            var last: PairingStatus?
            for _ in 0 ..< 70 {
                let attempt = try await start(app, key: key, proof: proof(store: store, key: key))
                #expect(attempt.approved)
                last = attempt
            }
            let response = try await app.testing().sendRequest(.DELETE, "pairing/\(last!.id)", beforeRequest: { req in try sign(&req, key: key) })
            #expect(response.status == .noContent)
            #expect(await store.contains(publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
        }
    }

    @Test("Expired approvals cannot authenticate, and pending request counts are bounded")
    func expiryAndCapacity() async throws {
        let clock = Mutex(Date())
        try await withPairing(now: { clock.withLock { $0 } }) { app, store, directory in
            let key = Curve25519.Signing.PrivateKey()
            let attempt = try await start(app, key: key)
            #expect(throws: (any Error).self) {
                try PairingStore.approve(code: attempt.code, directory: directory, now: Date().addingTimeInterval(301))
            }
            try PairingStore.approve(code: attempt.code, directory: directory)
            clock.withLock { $0 = $0.addingTimeInterval(301) }
            // Fresh timestamps are still checked: an old signed request cannot revive an attempt.
            let expired = try await app.testing().sendRequest(.GET, "pairing/\(attempt.id)", beforeRequest: { req in try sign(&req, key: key, now: clock.withLock { $0 }) })
            #expect(expired.status == .notFound)
            #expect(await !(store.contains(publicKey: key.publicKey.rawRepresentation.base64EncodedString())))
        }
        try await withPairing { app, _, _ in
            for _ in 0 ..< 32 {
                _ = try await start(app, key: Curve25519.Signing.PrivateKey())
            }
            let key = Curve25519.Signing.PrivateKey()
            let response = try await app.testing().sendRequest(.POST, "pairing", beforeRequest: { req in
                try req.content.encode(PairingRequest(publicKey: key.publicKey.rawRepresentation.base64EncodedString()), as: .json)
                try sign(&req, key: key)
            })
            #expect(response.status == .tooManyRequests)
        }
    }

    private func proof(store: PairingStore, key: Curve25519.Signing.PrivateKey) async -> String {
        let secret = await store.localSecret()
        return Data(HMAC<SHA256>.authenticationCode(for: key.publicKey.rawRepresentation.base64EncodedString().data(using: .utf8)!, using: SymmetricKey(data: Data(secret.utf8)))).base64EncodedString()
    }

    private func sign(_ request: inout TestingHTTPRequest, key: Curve25519.Signing.PrivateKey, now: Date = Date()) throws {
        let timestamp = String(now.timeIntervalSince1970)
        let nonce = UUID().uuidString
        let digest = SHA256.hash(data: Data(request.body.readableBytesView)).map { String(format: "%02x", $0) }.joined()
        let message = [request.method.rawValue, request.url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), timestamp, nonce, digest].joined(separator: "\n")
        request.headers.replaceOrAdd(name: "X-Unaru-Key", value: key.publicKey.rawRepresentation.base64EncodedString())
        try request.headers.replaceOrAdd(name: "X-Unaru-Signature", value: key.signature(for: Data(message.utf8)).base64EncodedString())
        request.headers.replaceOrAdd(name: "X-Unaru-Timestamp", value: timestamp)
        request.headers.replaceOrAdd(name: "X-Unaru-Nonce", value: nonce)
    }

    private func start(_ app: Application, key: Curve25519.Signing.PrivateKey, proof: String? = nil) async throws -> PairingStatus {
        let response = try await app.testing().sendRequest(.POST, "pairing", beforeRequest: { req in
            try req.content.encode(PairingRequest(publicKey: key.publicKey.rawRepresentation.base64EncodedString()), as: .json)
            if let proof {
                req.headers.replaceOrAdd(name: "X-Unaru-Local-Pairing", value: proof)
            }
            try sign(&req, key: key)
        })
        #expect(response.status == .ok)
        #expect(response.headers["Cache-Control"] == ["no-store"])
        return try response.content.decode(PairingStatus.self, using: JSONDecoder())
    }

    private func withPairing(now: @escaping @Sendable () -> Date = { Date() }, _ test: (Application, PairingStore, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PairingStore(directory: directory, now: now)
        try await withApp(configure: { app in try routes(app, connectionToken: nil, pairing: store) }) { app in try await test(app, store, directory) }
    }
}
