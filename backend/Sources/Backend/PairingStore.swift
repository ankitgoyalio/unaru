//
//  PairingStore.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Crypto
import Foundation
import Shared
import Vapor

/// Owns durable client authorization and short-lived owner-approved pairing attempts.
actor PairingStore {
    /// Private installation directory, shared only with the owner's approval command.
    private let directory: URL
    /// Durable public keys and a same-user local bootstrap secret.
    private var installation: Installation
    /// Recently accepted signed request nonces, bounded by their timestamp window.
    private var nonces: [String: Date] = [:]
    /// Pending attempts, bounded to prevent unapproved requests exhausting resources.
    private var attempts: [String: Attempt] = [:]
    /// Controllable time for expiry checks at the HTTP boundary.
    private let now: @Sendable () -> Date

    /// Opens or creates owner-only installation state; errors fail startup closed.
    init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.directory = directory
        self.now = now
        try Self.prepare(directory)
        let file = directory.appendingPathComponent("installation.json")
        if FileManager.default.fileExists(atPath: file.path) {
            installation = try JSONDecoder().decode(Installation.self, from: Data(contentsOf: file))
        } else {
            installation = Installation(localSecret: Self.secret(), publicKeys: [])
            try Self.write(installation, to: file)
        }
    }

    /// The default directory is stable across backend restarts and configurable for containers.
    static var defaultDirectory: URL {
        if let path = Environment.get("UNARU_DATA_DIRECTORY") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".unaru", isDirectory: true)
    }

    /// Generates cryptographically random bearer material using the system generator.
    static func secret() -> String {
        var generator = SystemRandomNumberGenerator()
        return Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }).base64EncodedString()
    }

    /// Supplies a bootstrap secret only to the same Mac user's protected Keychain.
    func localSecret() -> String {
        installation.localSecret
    }

    /// Accepts only durable credentials that have completed owner approval.
    func contains(publicKey: String) -> Bool {
        installation.publicKeys.contains(publicKey)
    }

    /// Verifies a fresh request without transmitting a reusable client credential.
    func authenticate(_ request: Request, approved: Bool = true) throws -> String {
        guard let key = request.headers.first(name: "X-Unaru-Key"),
              let encoded = request.headers.first(name: "X-Unaru-Signature"), let signature = Data(base64Encoded: encoded),
              let timestamp = request.headers.first(name: "X-Unaru-Timestamp"), let time = TimeInterval(timestamp), time.isFinite,
              abs(now().timeIntervalSince1970 - time) <= 60,
              let nonce = request.headers.first(name: "X-Unaru-Nonce"), UUID(uuidString: nonce) != nil,
              let bytes = Data(base64Encoded: key), let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes),
              !approved || installation.publicKeys.contains(key) else { throw Abort(.unauthorized) }
        nonces = nonces.filter { $0.value > now() }
        let scope = installation.publicKeys.contains(key) ? "approved:" : "pending:"
        let replayKey = scope + key + nonce
        let capacity = scope == "approved:" ? 4096 : 256
        guard nonces["approved:" + key + nonce] == nil, nonces["pending:" + key + nonce] == nil else { throw Abort(.unauthorized) }
        guard nonces.keys.filter({ $0.hasPrefix(scope) }).count < capacity else { throw Abort(.tooManyRequests) }
        let body = request.body.data.map { Data($0.readableBytesView) } ?? Data()
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let message = [request.method.rawValue, request.url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), timestamp, nonce, digest].joined(separator: "\n")
        guard publicKey.isValidSignature(signature, for: Data(message.utf8)) else { throw Abort(.unauthorized) }
        nonces[replayKey] = now().addingTimeInterval(120)
        return key
    }

    /// Starts a five-minute attempt, optionally proving ownership through same-user Keychain access.
    func start(publicKey: String, localProof: String?) throws -> PairingStatus {
        try prune()
        guard let bytes = Data(base64Encoded: publicKey), bytes.count == 32,
              (try? Curve25519.Signing.PublicKey(rawRepresentation: bytes)) != nil else { throw Abort(.badRequest) }
        // A verified client reconnect replaces its earlier attempt rather than consuming another slot.
        for (id, previous) in attempts where previous.publicKey == publicKey {
            attempts[id] = nil
            try removeFiles(id)
        }
        guard attempts.count < 32, installation.publicKeys.count < 64 || installation.publicKeys.contains(publicKey) else { throw Abort(.tooManyRequests) }
        let id = UUID().uuidString
        var code: String
        repeat {
            code = String(format: "%08d", Int.random(in: 0 ... 99_999_999))
        } while attempts.values.contains(where: { $0.code == code })
        let expected = Data(HMAC<SHA256>.authenticationCode(for: Data(publicKey.utf8), using: SymmetricKey(data: Data(installation.localSecret.utf8)))).base64EncodedString()
        let approved = installation.publicKeys.contains(publicKey) || (localProof.map { expected.utf8.secureCompare(to: $0.utf8) } ?? false)
        let attempt = Attempt(id: id, code: code, expiresAt: now().addingTimeInterval(300), publicKey: publicKey, previouslyApproved: installation.publicKeys.contains(publicKey))
        attempts[id] = attempt
        try Self.write(PendingApproval(id: id, code: code, expiresAt: attempt.expiresAt), to: pendingURL(id))
        if approved {
            try authorize(attempt)
        }
        return status(attempt)
    }

    /// Polls are restricted to the public key whose private key signed the request.
    func poll(id: String, publicKey: String) throws -> PairingStatus {
        try prune()
        guard let attempt = attempts[id], attempt.publicKey == publicKey else { throw Abort(.notFound) }
        let approval = directory.appendingPathComponent("\(id).approved")
        if FileManager.default.fileExists(atPath: approval.path) {
            try authorize(attempt)
            try FileManager.default.removeItem(at: approval)
        }
        return status(attempt)
    }

    /// Revokes a cancelled offer, including an approval racing with app cancellation.
    func cancel(id: String, publicKey: String) throws {
        guard let attempt = attempts[id], attempt.publicKey == publicKey else { throw Abort(.notFound) }
        if !attempt.previouslyApproved {
            installation.publicKeys.removeAll { $0 == attempt.publicKey }
            try persist()
        }
        attempts[id] = nil
        try removeFiles(id)
    }

    /// Approves exactly one unexpired code through owner-only filesystem access on the server.
    static func approve(code: String, directory: URL, now: Date = Date()) throws {
        guard code.count == 8, code.allSatisfy(\.isNumber) else { throw Abort(.badRequest, reason: "Enter the eight-digit code shown in Unaru.") }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let matches = try files.filter { $0.pathExtension == "pending" }.compactMap { file -> PendingApproval? in
            let pending = try JSONDecoder().decode(PendingApproval.self, from: Data(contentsOf: file))
            return pending.code == code && pending.expiresAt > now ? pending : nil
        }
        guard matches.count == 1, let pending = matches.first, UUID(uuidString: pending.id) != nil else {
            throw Abort(.notFound, reason: "Pairing code is missing or expired. Start Connect again in Unaru.")
        }
        try write(true, to: directory.appendingPathComponent("\(pending.id).approved"))
    }

    /// Persists approval before reporting success to the app.
    private func authorize(_ attempt: Attempt) throws {
        guard !installation.publicKeys.contains(attempt.publicKey) else { return }
        installation.publicKeys.append(attempt.publicKey)
        do { try persist() } catch {
            installation.publicKeys.removeAll { $0 == attempt.publicKey }
            throw error
        }
    }

    /// Encodes the nonsecret progress of an attempt.
    private func status(_ attempt: Attempt) -> PairingStatus {
        PairingStatus(id: attempt.id, code: attempt.code, expiresAt: attempt.expiresAt,
                      approved: installation.publicKeys.contains(attempt.publicKey))
    }

    /// Removes expired pending requests without revoking completed credentials.
    private func prune() throws {
        for (id, attempt) in attempts where attempt.expiresAt <= now() {
            attempts[id] = nil
            try removeFiles(id)
        }
        // Also remove requests abandoned by a previous server process.
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "pending" {
            if let pending = try? JSONDecoder().decode(PendingApproval.self, from: Data(contentsOf: file)), pending.expiresAt <= now() {
                try removeFiles(pending.id)
            }
        }
    }

    /// Resolves a server-generated attempt's metadata path.
    private func pendingURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).pending")
    }

    /// Removes command metadata after cancellation or expiry.
    private func removeFiles(_ id: String) throws {
        for suffix in ["pending", "approved"] {
            let url = directory.appendingPathComponent("\(id).\(suffix)")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Writes the durable registry with restrictive permissions.
    private func persist() throws {
        try Self.write(installation, to: directory.appendingPathComponent("installation.json"))
    }

    /// Creates an owner-only directory and refuses a symlink or a directory owned by another user.
    private static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw Abort(.internalServerError) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    /// Writes private data atomically without a world-readable intermediate file.
    private static func write(_ value: some Encodable, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw Abort(.internalServerError) }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard rename(temporary.path, url.path) == 0 else { throw Abort(.internalServerError) }
    }

    /// Durable installation authority, independent of the in-memory Kite session.
    private struct Installation: Codable {
        /// Secret disclosed only through the same-user local Keychain bootstrap.
        let localSecret: String
        /// Approved client public verification keys.
        var publicKeys: [String]
    }

    /// In-memory association between a comparison code and a candidate public key.
    private struct Attempt {
        /// Unguessable server-generated identifier.
        let id: String
        /// Human comparison code, usable only by the filesystem owner's command.
        let code: String
        /// Hard deadline for approval and polling.
        let expiresAt: Date
        /// Public verification key for the requesting app.
        let publicKey: String
        /// Reconnecting an existing client must not revoke its earlier approval on cancellation.
        let previouslyApproved: Bool
    }

    /// Minimal metadata read by the owner's approval command, containing no bearer credential.
    private struct PendingApproval: Codable {
        /// Server-generated attempt identifier used for the approval marker.
        let id: String
        /// Code displayed in the initiating app.
        let code: String
        /// Approval deadline, rechecked by the server before issuing access.
        let expiresAt: Date
    }
}
