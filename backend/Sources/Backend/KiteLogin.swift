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
    /// Missing configuration is distinct from recoverable secure-storage failure.
    enum ConfigurationError: Error {
        /// The helper has no complete Kite API configuration.
        case missingCredentials
    }

    /// A credential-free failure that permits retrying existing saved authorization.
    struct RecoveryFailure: Error {
        /// The recovery action shared with the app, without storage or provider diagnostics.
        let code: ConnectionProblem.Code
    }

    /// Credentials configured only in the backend environment.
    private let apiKey: String?
    /// The provider secret, never encoded in a response.
    private let apiSecret: String?
    /// The replaceable external HTTP boundary used by the real SDK.
    private let transport: any KiteHTTPTransport
    /// SDK routing remains production unless an isolated Debug helper supplies loopback.
    private let kiteConfiguration: KiteConfiguration
    /// A clock boundary for deterministic expiry tests.
    private let now: @Sendable () -> Date
    /// The lifetime of an authorized browser attempt.
    private let lifetime: TimeInterval
    /// Maximum time to wait for provider revocation.
    private let revocationTimeout: Duration
    /// Optional durable storage; standalone backends remain memory-only.
    private let store: any KiteSessionStore?
    /// Rejects restoration that resumes after newer login or logout authority.
    private var generation = UUID()
    /// Initial restoration remains retryable after temporary failures.
    private var restoreNeeded = true
    /// Only the newest restore validation may publish or invalidate saved authority.
    private var restoreRequestID: UUID?
    /// Confirmed invalidation must finish durable removal before any restoration.
    private var removalPending = false
    /// Limits cancellation cleanup to the matching browser authorization.
    private var cancellationID: String?
    /// The validated credential retained for saving without another exchange.
    private var validatedSession: SavedKiteSession?
    /// Credential-free outcome of the latest secure write.
    private var persistence: SessionStatus.Persistence?
    /// The newest attempt, replacing all previous callback authority.
    private var attempt: Attempt?
    /// The client whose exchange and profile retrieval have succeeded.
    private var authenticated: KiteClient?
    /// Only the latest authenticated profile read may publish identity or reject the session.
    private var profileRequestID: UUID?
    /// Superseded portfolio responses cannot publish or remove authority.
    private var holdingsRequestID: UUID?

    /// Creates an installation with production transport unless tests supply HTTP responses.
    init(
        apiKey: String? = Environment.get("KITE_API_KEY"),
        apiSecret: String? = Environment.get("KITE_API_SECRET"),
        transport: any KiteHTTPTransport = URLSessionKiteTransport(),
        store: any KiteSessionStore? = nil,
        kiteConfiguration: KiteConfiguration = try! KiteConfiguration(),
        lifetime: TimeInterval = 300,
        revocationTimeout: Duration = .seconds(5),
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.transport = transport
        self.store = store
        self.kiteConfiguration = kiteConfiguration
        self.lifetime = lifetime
        self.revocationTimeout = revocationTimeout
        self.now = now
    }

    /// Starts a new attempt using Kite's documented redirect_params query passthrough.
    func start() throws -> LoginAttempt {
        if removalPending {
            try finishRemoval()
        }
        guard let apiKey, !apiKey.isEmpty, let apiSecret, !apiSecret.isEmpty else {
            throw ConfigurationError.missingCredentials
        }
        let client = try KiteClient(apiKey: apiKey, configuration: kiteConfiguration, transport: transport)
        let id = UUID().uuidString
        let state = UUID().uuidString + UUID().uuidString
        let deadline = now().addingTimeInterval(lifetime)
        let browserURL = try client.loginURL(redirectParameters: "state=\(state)")
        generation = UUID()
        restoreNeeded = false
        removalPending = false
        validatedSession = nil
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
            let session = try await current.client.exchangeRequestToken(requestToken, apiSecret: apiSecret)
            guard isCurrent(current.id) else { throw Abort(.conflict, reason: "Login was superseded or expired.") }
            attempt?.accessToken = session.accessToken
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
            return LoginStatus(state: .signedIn, profile: profile, persistence: persistence)
        }
        guard current.result == .pending, current.exchanged else { return LoginStatus(state: current.result) }
        do {
            let profile = try await current.client.profile()
            guard isCurrent(id) else { return LoginStatus(state: .failed) }
            try Task.checkCancellation()
            let identity = Self.identity(profile)
            if let token = current.accessToken {
                let session = SavedKiteSession(userID: profile.userID, accessToken: token, loginAttemptID: id)
                validatedSession = session
                saveCurrentSession()
            }
            attempt?.profile = identity
            authenticated = current.client
            return LoginStatus(state: .signedIn, profile: identity, persistence: persistence)
        } catch {
            guard isCurrent(id) else { return LoginStatus(state: .failed) }
            if Self.isAuthenticationRejection(error) {
                attempt?.result = .failed
                return LoginStatus(state: .failed)
            }
            throw Abort(.serviceUnavailable, reason: "Kite profile is temporarily unavailable. Retry in Unaru.")
        }
    }

    /// Cancels only matching authority, including an acknowledged attempt after restart.
    func cancel(id: String) throws {
        if attempt?.id == id || validatedSession?.loginAttemptID == id || (removalPending && cancellationID == id) {
            try removeAuthority(cancellationID: id)
        } else if attempt == nil, authenticated == nil, let apiKey,
                  try store?.load(apiKey: apiKey)?.loginAttemptID == id
        {
            try removeAuthority(cancellationID: id)
        }
    }

    /// Detaches all old authority before remote work; completion cannot mutate a newer session.
    func logout() async throws -> LogoutResult {
        let client = authenticated ?? attempt?.client
        try removeAuthority()
        guard let client else { return LogoutResult(revocation: .unconfirmed) }
        let confirmed = await BoundedRevocation().run(client: client, timeout: revocationTimeout)
        return LogoutResult(revocation: confirmed ? .confirmed : .unconfirmed)
    }

    /// Reads an authenticated profile without exposing the SDK's token-bearing session.
    func profile() async throws -> AccountProfile {
        try await restore()
        guard let client = authenticated else { throw Abort(.unauthorized, reason: "Kite sign-in required.") }
        let requestID = UUID()
        profileRequestID = requestID
        let profile: KiteUserProfile
        do {
            profile = try await client.profile()
        } catch {
            guard authenticated === client, profileRequestID == requestID else {
                throw Abort(.serviceUnavailable, reason: "Kite profile request was superseded.")
            }
            if Self.isAuthenticationRejection(error) {
                try removeAuthority()
                throw Abort(.unauthorized, reason: "Kite sign-in required.")
            }
            throw Abort(.serviceUnavailable, reason: "Kite profile is temporarily unavailable.")
        }
        guard authenticated === client, profileRequestID == requestID else {
            throw Abort(.serviceUnavailable, reason: "Kite profile request was superseded.")
        }
        try Task.checkCancellation()
        if let validatedSession, profile.userID != validatedSession.userID {
            try removeAuthority()
            throw Abort(.unauthorized, reason: "Kite sign-in required.")
        }
        return Self.identity(profile)
    }

    /// Reads securities through the pinned SDK, checking authority after every suspension.
    func holdings() async throws -> SecuritiesHoldings {
        try await restore()
        guard let client = authenticated else { throw Abort(.unauthorized) }
        let requestID = UUID()
        holdingsRequestID = requestID
        do {
            let rows = try await client.holdings()
            guard authenticated === client, holdingsRequestID == requestID else { throw CancellationError() }
            try Task.checkCancellation()
            return SecuritiesHoldings(holdings: SecuritiesHoldingSource.normalize(rows), retrievedAt: now())
        } catch {
            guard authenticated === client, holdingsRequestID == requestID else {
                throw Abort(.serviceUnavailable, reason: "Holdings request was superseded.")
            }
            if Self.isAuthenticationRejection(error) {
                try removeAuthority()
                throw Abort(.unauthorized)
            }
            throw RecoveryFailure(code: .portfolioUnavailable)
        }
    }

    /// Reports only whether a completed backend-held session exists.
    func session() async throws -> SessionStatus {
        try await restore()
        return SessionStatus(state: authenticated == nil ? .signedOut : .signedIn, persistence: authenticated == nil ? nil : persistence ?? .memoryOnly)
    }

    /// Retries secure saving of current authority without browser or exchange work.
    func retrySave() async throws -> SessionStatus {
        guard authenticated != nil else { throw Abort(.unauthorized, reason: "Kite sign-in required.") }
        saveCurrentSession()
        return try await session()
    }

    /// Synchronous storage cannot resume after a newer actor generation has taken authority.
    private func saveCurrentSession() {
        guard let store, let apiKey, let validatedSession else {
            persistence = .memoryOnly
            return
        }
        do {
            try store.save(validatedSession, apiKey: apiKey)
            persistence = .saved
        } catch {
            persistence = .saveFailed
        }
    }

    /// Detaches authority before storage work; cancellation never removes another attempt.
    private func removeAuthority(cancellationID: String? = nil) throws {
        generation = UUID()
        authenticated = nil
        validatedSession = nil
        attempt = nil
        restoreNeeded = false
        removalPending = true
        self.cancellationID = cancellationID
        try finishRemoval()
    }

    /// Retries durable cleanup without restoring rejected or cancelled credentials.
    private func finishRemoval() throws {
        do {
            if let apiKey {
                if let cancellationID {
                    if try store?.load(apiKey: apiKey)?.loginAttemptID == cancellationID {
                        try store?.delete(apiKey: apiKey)
                    }
                } else {
                    try store?.delete(apiKey: apiKey)
                }
            }
            removalPending = false
            cancellationID = nil
        } catch {
            throw Abort(.serviceUnavailable, reason: "Saved Kite authorization could not be removed.")
        }
    }

    /// Validates saved authorization before publishing any identity; errors preserve the item.
    private func restore() async throws {
        if removalPending {
            try finishRemoval()
            return
        }
        guard restoreNeeded else { return }
        guard let store, let apiKey, !apiKey.isEmpty else {
            restoreNeeded = false
            return
        }
        let revision = generation
        let requestID = UUID()
        restoreRequestID = requestID
        let stored: SavedKiteSession?
        do {
            stored = try store.load(apiKey: apiKey)
        } catch {
            throw RecoveryFailure(code: .sessionStorageUnavailable)
        }
        guard let session = stored else {
            restoreNeeded = false
            return
        }
        do {
            let client = try KiteClient(apiKey: apiKey, accessToken: session.accessToken, configuration: kiteConfiguration, transport: transport)
            let profile: KiteUserProfile
            do { profile = try await client.profile() }
            catch {
                guard generation == revision, restoreRequestID == requestID else { throw CancellationError() }
                if Self.isAuthenticationRejection(error) {
                    try removeAuthority()
                    return
                }
                throw error
            }
            guard generation == revision, restoreRequestID == requestID else { throw CancellationError() }
            try Task.checkCancellation()
            guard profile.userID == session.userID else {
                try removeAuthority()
                return
            }
            authenticated = client
            validatedSession = session
            persistence = .saved
            restoreNeeded = false
        } catch let error as any AbortError {
            throw error
        } catch {
            throw RecoveryFailure(code: .kiteSessionUnavailable)
        }
    }

    /// Checks attempt authority and expiry after an external request resumes.
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
        return AccountProfile(
            name: profile.userName, userID: profile.userID, avatarURL: safe,
            email: profile.email, broker: profile.broker, accountType: profile.userType,
            exchanges: profile.exchanges.map(\.rawValue), products: profile.products.map(\.rawValue),
            orderTypes: profile.orderTypes.map(\.rawValue),
        )
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
        /// Exchange credential retained only until account validation.
        var accessToken: String?
        /// Pending or terminal failure state.
        var result: LoginStatus.State = .pending
        /// The successfully fetched public identity.
        var profile: AccountProfile?
    }
}
