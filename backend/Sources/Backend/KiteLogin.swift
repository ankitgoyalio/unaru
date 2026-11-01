//
//  KiteLogin.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation
import KiteConnect
import Shared
import Vapor

/// Serializes the single installation's login and rejects obsolete async results.
actor KiteLogin {
    /// Credentials configured only in the backend environment.
    private let apiKey: String?
    /// The provider secret, never encoded in a response.
    private let apiSecret: String?
    /// The replaceable external HTTP boundary used by the real SDK.
    private let transport: any KiteHTTPTransport
    /// A clock boundary for deterministic expiry tests.
    private let now: @Sendable () -> Date
    /// The lifetime of an authorized browser attempt.
    private let lifetime: TimeInterval
    /// The newest attempt, replacing all previous callback authority.
    private var attempt: Attempt?
    /// The client whose exchange and profile retrieval have succeeded.
    private var authenticated: KiteClient?

    /// Creates an installation with production transport unless tests supply HTTP responses.
    init(
        apiKey: String? = Environment.get("KITE_API_KEY"),
        apiSecret: String? = Environment.get("KITE_API_SECRET"),
        transport: any KiteHTTPTransport = URLSessionKiteTransport(),
        lifetime: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.transport = transport
        self.lifetime = lifetime
        self.now = now
    }

    /// Starts a new attempt using Kite's documented redirect_params query passthrough.
    func start() throws -> LoginAttempt {
        guard let apiKey, !apiKey.isEmpty, let apiSecret, !apiSecret.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "Configure Kite credentials on the backend.")
        }
        let client = try KiteClient(apiKey: apiKey, transport: transport)
        let id = UUID().uuidString
        let state = UUID().uuidString + UUID().uuidString
        let deadline = now().addingTimeInterval(lifetime)
        let browserURL = try client.loginURL(redirectParameters: "state=\(state)")
        attempt = Attempt(id: id, state: state, deadline: deadline, client: client)
        authenticated = nil
        return LoginAttempt(id: id, browserURL: browserURL, expiresAt: deadline)
    }

    /// Consumes callback authority before any suspension, including failed exchanges.
    func callback(state: String, requestToken: String?, status: String?) async throws {
        guard var current = attempt, current.state == state, current.deadline > now(), !current.consumed else {
            throw Abort(.badRequest, reason: "Login callback is invalid or expired.")
        }
        current.consumed = true
        attempt = current
        guard status == "success", let requestToken, !requestToken.isEmpty, let apiSecret else {
            attempt?.result = .failed
            throw Abort(.badRequest, reason: "Kite login was not completed. Return to Unaru to try again.")
        }
        do {
            _ = try await current.client.exchangeRequestToken(requestToken, apiSecret: apiSecret)
            guard isCurrent(current.id) else { throw Abort(.conflict, reason: "Login was superseded or expired.") }
            attempt?.exchanged = true
        } catch {
            if isCurrent(current.id) {
                attempt?.result = .failed
            }
            throw Abort(.badGateway, reason: "Kite login could not complete. Return to Unaru to try again.")
        }
    }

    /// Observes completion, retrying only the read-only profile operation after temporary failures.
    func status(id: String) async throws -> LoginStatus {
        guard let current = attempt, current.id == id else { return LoginStatus(state: .failed) }
        guard current.deadline > now() else {
            attempt = nil
            return LoginStatus(state: .expired)
        }
        if let profile = current.profile {
            return LoginStatus(state: .signedIn, profile: profile)
        }
        guard current.result == .pending, current.exchanged else { return LoginStatus(state: current.result) }
        do {
            let profile = try await current.client.profile()
            guard isCurrent(id) else { return LoginStatus(state: .failed) }
            let identity = Self.identity(profile)
            attempt?.profile = identity
            authenticated = current.client
            return LoginStatus(state: .signedIn, profile: identity)
        } catch {
            guard isCurrent(id) else { return LoginStatus(state: .failed) }
            if Self.isAuthenticationRejection(error) {
                attempt?.result = .failed
                return LoginStatus(state: .failed)
            }
            throw Abort(.serviceUnavailable, reason: "Kite profile is temporarily unavailable. Retry in Unaru.")
        }
    }

    /// Invalidates callback and in-flight profile authority when the app cancels.
    func cancel(id: String) {
        if let current = attempt, current.id == id {
            if authenticated === current.client {
                authenticated = nil
            }
            attempt = nil
        }
    }

    /// Reads an authenticated profile without exposing the SDK's token-bearing session.
    func profile() async throws -> AccountProfile {
        guard let client = authenticated else { throw Abort(.unauthorized, reason: "Kite sign-in required.") }
        do {
            let profile = try await client.profile()
            guard authenticated === client else { throw Abort(.conflict) }
            return Self.identity(profile)
        } catch {
            if Self.isAuthenticationRejection(error) {
                if authenticated === client {
                    authenticated = nil
                    if attempt?.client === client {
                        attempt = nil
                    }
                }
                throw Abort(.unauthorized, reason: "Kite sign-in required.")
            }
            throw Abort(.serviceUnavailable, reason: "Kite profile is temporarily unavailable.")
        }
    }

    /// Reports only whether a completed backend-held session exists.
    func session() -> SessionStatus {
        SessionStatus(state: authenticated == nil ? .signedOut : .signedIn)
    }

    /// Checks revision and expiry after an external request resumes.
    private func isCurrent(_ id: String) -> Bool {
        attempt?.id == id && (attempt?.deadline ?? .distantPast) > now()
    }

    /// Maps only a provider token rejection to a requirement for reauthentication.
    private static func isAuthenticationRejection(_ error: any Error) -> Bool {
        if case let KiteError.api(problem) = error {
            return problem.errorType == "TokenException"
        }
        return false
    }

    /// Restricts avatar requests to public HTTPS addresses without credentials or query data.
    private static func identity(_ profile: KiteUserProfile) -> AccountProfile {
        let url = profile.avatarURL.flatMap(URL.init(string:))
        let safe = url.flatMap { url -> URL? in
            guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { return nil }
            return url
        }
        return AccountProfile(name: profile.userName, userID: profile.userID, avatarURL: safe)
    }

    /// In-memory attempt data, discarded on restart or replacement.
    private struct Attempt {
        /// Identifier available only to authorized clients.
        let id: String
        /// Independent random callback correlation value.
        let state: String
        /// Hard deadline, including exchange and profile work.
        let deadline: Date
        /// An SDK client isolated to this attempt.
        let client: KiteClient
        /// Whether the callback has already been claimed.
        var consumed = false
        /// Whether the single token exchange completed.
        var exchanged = false
        /// Pending or terminal failure state.
        var result: LoginStatus.State = .pending
        /// The successfully fetched public identity.
        var profile: AccountProfile?
    }
}
