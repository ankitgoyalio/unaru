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
    /// Durable hashes and a same-user local bootstrap secret.
    private var installation: Installation
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
            installation = Installation(localSecret: Self.secret(), credentials: [])
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
    func accepts(_ credential: String) -> Bool {
        installation.credentials.contains(Self.digest(credential))
    }

    /// Starts a five-minute attempt, optionally proving ownership through same-user Keychain access.
    func start(credential: String, localProof: String?) throws -> PairingStatus {
        try prune()
        guard credential.utf8.count >= 40, credential.utf8.count <= 128,
              credential.utf8.allSatisfy({ (33 ... 126).contains($0) }) else { throw Abort(.badRequest) }
        guard attempts.count < 32, installation.credentials.count < 64 else { throw Abort(.tooManyRequests) }
        let id = UUID().uuidString
        var code: String
        repeat {
            code = String(format: "%08d", Int.random(in: 0 ... 99_999_999))
        } while attempts.values.contains(where: { $0.code == code })
        let approved = localProof.map { installation.localSecret.utf8.secureCompare(to: $0.utf8) } ?? false
        let attempt = Attempt(id: id, code: code, expiresAt: now().addingTimeInterval(300), digest: Self.digest(credential))
        attempts[id] = attempt
        try Self.write(PendingApproval(id: id, code: code, expiresAt: attempt.expiresAt), to: pendingURL(id))
        if approved {
            try authorize(attempt)
        }
        return status(attempt)
    }

    /// Polls require the offered secret, rather than the visible comparison code or ID.
    func poll(id: String, credential: String) throws -> PairingStatus {
        try prune()
        guard let attempt = attempts[id], attempt.digest == Self.digest(credential) else { throw Abort(.notFound) }
        let approval = directory.appendingPathComponent("\(id).approved")
        if FileManager.default.fileExists(atPath: approval.path) {
            try authorize(attempt)
            try FileManager.default.removeItem(at: approval)
        }
        return status(attempt)
    }

    /// Revokes a cancelled offer, including an approval racing with app cancellation.
    func cancel(id: String, credential: String) throws {
        guard let attempt = attempts[id], attempt.digest == Self.digest(credential) else { throw Abort(.notFound) }
        installation.credentials.removeAll { $0 == attempt.digest }
        try persist()
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

    /// Hashes high-entropy credentials so the persistent registry cannot be used as a bearer token.
    private static func digest(_ credential: String) -> String {
        SHA256.hash(data: Data(credential.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Persists approval before reporting success to the app.
    private func authorize(_ attempt: Attempt) throws {
        guard !installation.credentials.contains(attempt.digest) else { return }
        installation.credentials.append(attempt.digest)
        do { try persist() } catch {
            installation.credentials.removeAll { $0 == attempt.digest }
            throw error
        }
    }

    /// Encodes the nonsecret progress of an attempt.
    private func status(_ attempt: Attempt) -> PairingStatus {
        PairingStatus(id: attempt.id, code: attempt.code, expiresAt: attempt.expiresAt,
                      approved: installation.credentials.contains(attempt.digest))
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
        /// Hashes of approved client-generated credentials.
        var credentials: [String]
    }

    /// In-memory association between a public code and a secret credential hash.
    private struct Attempt {
        /// Unguessable server-generated identifier.
        let id: String
        /// Human comparison code, usable only by the filesystem owner's command.
        let code: String
        /// Hard deadline for approval and polling.
        let expiresAt: Date
        /// Hash of the candidate credential.
        let digest: String
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
