//
//  LogoutResult.swift
//  unaru
//
//  Created by Ankit Goyal on 03/11/2026.

/// The outcome of a local logout, without disclosing Kite credentials.
public struct LogoutResult: Codable, Sendable {
    /// Only a positive Kite response confirms remote token invalidation.
    public enum Revocation: String, Codable, Sendable {
        /// Kite positively acknowledged invalidation of the current API token.
        case confirmed
        /// Kite revocation was negative, ambiguous, unavailable, or timed out.
        case unconfirmed
    }

    /// Returned only after local authority and any durable authorization are removed.
    public let revocation: Revocation

    /// Creates a logout response after local session authority has been cleared.
    public init(revocation: Revocation) {
        self.revocation = revocation
    }
}
