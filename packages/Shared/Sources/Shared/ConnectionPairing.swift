//
//  ConnectionPairing.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation

/// A client-generated public key offered for approval by the backend owner.
public struct PairingRequest: Codable, Sendable {
    /// Public verification key; the private signing key stays in the app’s Keychain.
    public let publicKey: String

    /// Creates a request without exposing private key material.
    public init(publicKey: String) {
        self.publicKey = publicKey
    }
}

/// Public progress for a bounded connection approval attempt.
public struct PairingStatus: Codable, Sendable {
    /// The server-generated attempt identifier.
    public let id: String
    /// A short code the owner compares before approving on the server.
    public let code: String
    /// The attempt's absolute expiry time.
    public let expiresAt: Date
    /// Whether the offered credential can now authorize app requests.
    public let approved: Bool

    /// Creates an approval response containing no authorization secret.
    public init(id: String, code: String, expiresAt: Date, approved: Bool) {
        self.id = id
        self.code = code
        self.expiresAt = expiresAt
        self.approved = approved
    }
}
