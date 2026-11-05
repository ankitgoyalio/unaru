//
//  KiteSessionStore.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation

/// Durable authorization owned exclusively by the helper, never an HTTP payload.
struct SavedKiteSession: Codable, Sendable {
    /// The account confirmed by Kite before this token was saved.
    let userID: String
    /// The provider credential, never logged or sent to the app.
    let accessToken: String
    /// Credential-free origin used to scope cancellation across helper replacement.
    var loginAttemptID: String? = nil
}

/// Atomic local operations, serialized with login authority by the coordinator.
/// Absence is nil; access and decoding failures throw without deleting authorization.
protocol KiteSessionStore: Sendable {
    /// Reads authorization only for this configuration.
    func load(apiKey: String) throws -> SavedKiteSession?
    /// Atomically replaces authorization after account validation.
    func save(_ session: SavedKiteSession, apiKey: String) throws
    /// Removes authorization before logout can report success; absence succeeds.
    func delete(apiKey: String) throws
}
