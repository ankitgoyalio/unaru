//
//  KiteLogin.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation

/// The identity displayed by the app, without any broker credentials.
public struct AccountProfile: Codable, Sendable, Equatable {
    /// The full Kite account name.
    public let name: String
    /// The broker's permanent account identifier.
    public let userID: String
    /// An optional public HTTPS avatar address.
    public let avatarURL: URL?

    /// Registered contact address, when supplied by Kite.
    public let email: String?
    /// Broker code reported by Kite.
    public let broker: String?
    /// Account type reported by Kite.
    public let accountType: String?
    /// Enabled exchange codes; nil means the provider omitted the field.
    public let exchanges: [String]?
    /// Enabled product codes, preserving provider meaning.
    public let products: [String]?
    /// Enabled order type codes; an empty list differs from an omitted field.
    public let orderTypes: [String]?

    /// Creates the app-visible subset of a Kite profile.
    public init(
        name: String, userID: String, avatarURL: URL? = nil,
        email: String? = nil, broker: String? = nil, accountType: String? = nil,
        exchanges: [String]? = nil, products: [String]? = nil, orderTypes: [String]? = nil,
    ) {
        self.name = name
        self.userID = userID
        self.avatarURL = avatarURL
        self.email = email
        self.broker = broker
        self.accountType = accountType
        self.exchanges = exchanges
        self.products = products
        self.orderTypes = orderTypes
    }
}

/// An authorized attempt and the public provider URL opened in the browser.
public struct LoginAttempt: Codable, Sendable {
    /// The opaque identifier used only on authorized app operations.
    public let id: String
    /// The provider login URL, containing no app authorization or broker tokens.
    public let browserURL: URL
    /// The absolute deadline for completing this attempt.
    public let expiresAt: Date

    /// Creates a bounded browser handoff.
    public init(id: String, browserURL: URL, expiresAt: Date) {
        self.id = id
        self.browserURL = browserURL
        self.expiresAt = expiresAt
    }
}

/// The observable result of one login attempt.
public struct LoginStatus: Codable, Sendable {
    /// The stages that do not disclose credentials.
    public enum State: String, Codable, Sendable {
        /// The browser has not returned or exchange is still running.
        case pending
        /// Exchange and a separate profile request have both succeeded.
        case signedIn
        /// Login was denied, cancelled, rejected, or superseded.
        case failed
        /// The attempt's deadline passed.
        case expired
    }

    /// The current stage.
    public let state: State
    /// Present only after successful authentication and profile retrieval.
    public let profile: AccountProfile?

    /// Creates a credential-free attempt result.
    public init(state: State, profile: AccountProfile? = nil) {
        self.state = state
        self.profile = profile
    }
}
