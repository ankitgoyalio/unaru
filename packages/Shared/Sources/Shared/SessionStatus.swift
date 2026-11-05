//
//  SessionStatus.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

/// The backend's current Kite authentication status, disclosed only to authorized clients.
public struct SessionStatus: Codable, Sendable {
    /// The Kite session state. Additional states accompany future authentication support.
    public enum State: String, Codable, Sendable {
        /// The backend has no authenticated Kite session.
        case signedOut
        /// The backend has completed Kite authentication and profile retrieval.
        case signedIn
    }

    /// Whether helper-held authorization survives quitting; absent on older backends.
    public enum Persistence: String, Codable, Sendable {
        /// This backend intentionally has no durable session store.
        case memoryOnly
        /// The validated authorization is saved securely.
        case saved
        /// Current authorization is usable but secure saving failed.
        case saveFailed
    }

    /// Credential-free persistence information, separate from Kite validity.
    public let persistence: Persistence?

    /// The current authentication state.
    public let state: State

    /// Creates a session-status response without broker credentials.
    public init(state: State, persistence: Persistence? = nil) {
        self.state = state
        self.persistence = persistence
    }
}
