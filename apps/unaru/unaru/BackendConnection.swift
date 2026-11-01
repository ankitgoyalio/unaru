//
//  BackendConnection.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import AppKit
    import Combine
    import Foundation
    import Shared

    /// Owns the saved backend connection and the currently verified result.
    @MainActor
    final class BackendConnection: ObservableObject {
        /// The app-visible state of the current connection, never a cached identity.
        enum Phase: Equatable {
            /// No complete saved configuration exists.
            case setup
            /// The app is making an authorized session-status request.
            case checking
            /// The backend is reachable and requires Kite authentication.
            case signedOut
            /// An authorized browser attempt is pending.
            case loggingIn
            /// A temporary profile/status error can retry the same attempt.
            case loginUnavailable
            /// The browser attempt failed and can be started again.
            case loginFailed
            /// Exchange and profile retrieval have both completed.
            case signedIn(AccountProfile)
            /// The user must correct connection settings.
            case configurationError(String)
            /// The server configuration needs repair, rather than Kite reauthentication.
            case backendError
            /// A temporary connection or server failure permits retry.
            case unavailable
        }

        /// The state presented by every main window.
        @Published private(set) var phase: Phase = .setup {
            didSet { scheduleRevalidation() }
        }

        /// The nonsecret address loaded for Settings.
        @Published private(set) var address = ""
        /// Storage for the address and Keychain credential.
        private let storage = ConnectionStorage()
        /// The current request, cancelled whenever configuration changes.
        private var task: Task<Void, Never>?
        /// One cancellable delay between successful validations; never a second request loop.
        private var revalidationTask: Task<Void, Never>?
        /// A monotonically changing identifier that rejects obsolete results.
        private var revision = 0
        /// The current validated connection information.
        private var configuration: (url: URL, token: String)?
        /// The app's current attempt, retained only for retrying profile/status reads.
        private var activeAttempt: LoginAttempt?
        /// An ephemeral transport that refuses redirects carrying credentials.
        private let session = URLSession(configuration: .ephemeral, delegate: ConnectionRedirectPolicy(), delegateQueue: nil)

        /// Restores configuration and verifies the server on launch.
        init() {
            address = storage.defaults.string(forKey: "backendAddress") ?? ""
            do {
                let token = try storage.readToken()
                guard !address.isEmpty, !token.isEmpty else { return }
                configuration = try Self.validate(address: address, token: token)
                verify()
            } catch is ConnectionStorage.StorageFailure {
                phase = .configurationError("The saved connection could not be read. Unlock Keychain, then open Settings to save your connection again.")
            } catch {
                phase = .configurationError("Open Settings to check the backend address and connection token.")
            }
        }

        deinit {
            task?.cancel()
            revalidationTask?.cancel()
        }

        /// Rechecks provider authentication while the app remains open, including after sleep.
        private func scheduleRevalidation() {
            revalidationTask?.cancel()
            revalidationTask = nil
            guard case .signedIn = phase else { return }
            var interval: TimeInterval = 60
            #if DEBUG
                // Accelerate time only in isolated UI tests, never in production storage.
                if storage.service.contains(".uitests."),
                   let value = ProcessInfo.processInfo.environment["UNARU_TEST_REVALIDATION_SECONDS"],
                   let seconds = TimeInterval(value), seconds.isFinite, seconds >= 1, seconds <= 60
                {
                    interval = seconds
                }
            #endif
            revalidationTask = Task { [weak self, interval] in
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { return }
                guard !Task.isCancelled, let self, case .signedIn = phase else { return }
                verify(preservingIdentity: true)
            }
        }

        /// Loads the token directly from Keychain for the secure Settings field.
        func savedToken() throws -> String {
            try storage.readToken()
        }

        /// Invalidates prior results, saves valid settings, and verifies the new connection.
        @discardableResult
        func save(address: String, token: String) -> Bool {
            cancelLogin()
            configuration = nil
            phase = .setup
            do {
                let validated = try Self.validate(address: address, token: token)
                try storage.save(address: validated.url.absoluteString, token: token)
                self.address = validated.url.absoluteString
                configuration = validated
                verify()
                return true
            } catch let error as InvalidConfiguration {
                phase = .configurationError(error.message)
            } catch {
                phase = .configurationError("The connection could not be saved in Keychain. Unlock Keychain and try again in Settings.")
            }
            return false
        }

        /// Retries the saved connection without treating network failures as expired Kite authentication.
        func verify() {
            verify(preservingIdentity: false)
        }

        /// Keeps a validated footer stable during a background read, then applies the same error policy.
        private func verify(preservingIdentity: Bool) {
            guard let configuration else { return }
            revalidationTask?.cancel()
            revalidationTask = nil
            revision += 1
            let currentRevision = revision
            task?.cancel()
            if !preservingIdentity {
                phase = .checking
            }
            task = Task {
                do {
                    let data = try await send("session", configuration: configuration)
                    guard !Task.isCancelled, currentRevision == revision else { return }
                    let status = try JSONDecoder().decode(SessionStatus.self, from: data)
                    switch status.state {
                    case .signedOut:
                        phase = .signedOut
                    case .signedIn:
                        let profileData = try await send("profile", configuration: configuration)
                        let profile = try JSONDecoder().decode(AccountProfile.self, from: profileData)
                        guard !Task.isCancelled, currentRevision == revision else { return }
                        phase = .signedIn(profile)
                    }
                } catch {
                    guard !Task.isCancelled, currentRevision == revision else { return }
                    switch error {
                    case LoginFailure.signedOut: phase = .signedOut
                    case LoginFailure.configuration:
                        phase = .configurationError("The backend rejected the connection token. Check the token in Settings.")
                    case LoginFailure.backendConfiguration: phase = .backendError
                    default: phase = .unavailable
                    }
                }
            }
        }

        /// Creates an authorized attempt and opens the system's default browser.
        func signIn() {
            guard let configuration, phase == .signedOut || phase == .loginFailed || (phase == .loginUnavailable && activeAttempt == nil) else { return }
            revision += 1
            let currentRevision = revision
            task?.cancel()
            activeAttempt = nil
            phase = .loggingIn
            task = Task {
                do {
                    let data = try await send("login", method: "POST", configuration: configuration)
                    let attempt = try JSONDecoder().decode(LoginAttempt.self, from: data)
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    activeAttempt = attempt
                    let url = attempt.browserURL
                    guard url.scheme == "https", url.host == "kite.zerodha.com", url.path == "/connect/login",
                          url.user == nil, url.password == nil, url.fragment == nil else { throw LoginFailure.failed }
                    #if DEBUG
                        if storage.service.contains(".uitests."), ProcessInfo.processInfo.environment["UNARU_TEST_BROWSER"] == "1" {
                            _ = try await send("test/browser", method: "POST", configuration: configuration, body: data)
                        } else {
                            guard NSWorkspace.shared.open(url) else { throw LoginFailure.failed }
                        }
                    #else
                        guard NSWorkspace.shared.open(url) else { throw LoginFailure.failed }
                    #endif
                    try await observe(attempt, configuration: configuration, revision: currentRevision)
                } catch {
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    showLoginError(error)
                }
            }
        }

        /// Retries the pending read operation without replaying a consumed request token.
        func retryLogin() {
            guard phase == .loginUnavailable else { return }
            guard let configuration, let attempt = activeAttempt else { signIn(); return }
            revision += 1
            let currentRevision = revision
            task?.cancel()
            phase = .loggingIn
            task = Task {
                do {
                    try await observe(attempt, configuration: configuration, revision: currentRevision)
                } catch {
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    showLoginError(error)
                }
            }
        }

        /// Makes earlier browser/profile results obsolete immediately, then revokes the server attempt.
        func cancelLogin() {
            revision += 1
            task?.cancel()
            let oldAttempt = activeAttempt
            activeAttempt = nil
            phase = .signedOut
            if let oldAttempt, let configuration {
                Task { _ = try? await send("login/\(oldAttempt.id)", method: "DELETE", configuration: configuration) }
            }
        }

        /// Polls only the authorized attempt until success, terminal failure, or a bounded deadline.
        private func observe(_ attempt: LoginAttempt, configuration: (url: URL, token: String), revision currentRevision: Int) async throws {
            let deadline = min(attempt.expiresAt, Date().addingTimeInterval(300))
            while Date() < deadline {
                let data = try await send("login/\(attempt.id)", configuration: configuration)
                let result = try JSONDecoder().decode(LoginStatus.self, from: data)
                guard !Task.isCancelled, revision == currentRevision else { return }
                switch result.state {
                case .pending:
                    try await Task.sleep(for: .seconds(1))
                case .signedIn:
                    guard let profile = result.profile else { throw LoginFailure.failed }
                    activeAttempt = nil
                    phase = .signedIn(profile)
                    return
                case .failed, .expired:
                    activeAttempt = nil
                    phase = .loginFailed
                    return
                }
            }
            cancelLogin()
            phase = .loginFailed
        }

        /// Sends credentials only in headers and refuses redirects through the shared transport.
        private func send(_ path: String, method: String = "GET", configuration: (url: URL, token: String), body: Data? = nil) async throws -> Data {
            var request = URLRequest(url: configuration.url.appendingPathComponent(path))
            request.httpMethod = method
            request.httpBody = body
            request.timeoutInterval = 15
            request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw LoginFailure.unavailable }
            switch response.statusCode {
            case 200 ... 299: return data
            case 401, 403:
                let problem = try? JSONDecoder().decode(ConnectionProblem.self, from: data)
                if problem?.code == .kiteSignInRequired {
                    throw LoginFailure.signedOut
                }
                throw LoginFailure.configuration
            case 503:
                let problem = try? JSONDecoder().decode(ConnectionProblem.self, from: data)
                if problem?.code == .backendNotConfigured {
                    throw LoginFailure.backendConfiguration
                }
                throw LoginFailure.unavailable
            default: throw LoginFailure.unavailable
            }
        }

        /// Maps login errors to an actionable state without displaying server diagnostics.
        private func showLoginError(_ error: any Error) {
            switch error {
            case LoginFailure.configuration:
                activeAttempt = nil
                phase = .configurationError("The backend rejected the connection token. Check the token in Settings.")
            case LoginFailure.signedOut:
                activeAttempt = nil
                phase = .signedOut
            case LoginFailure.backendConfiguration:
                phase = .backendError
            case LoginFailure.failed:
                cancelLogin()
                phase = .loginFailed
            default:
                phase = .loginUnavailable
            }
        }

        /// Safe error categories for the browser flow.
        private enum LoginFailure: Error {
            /// App authorization was rejected.
            case configuration
            /// The authorized backend has no valid Kite session.
            case signedOut
            /// The backend connection token has not been configured.
            case backendConfiguration
            /// Browser handoff could not begin.
            case failed
            /// A read or connection can be retried.
            case unavailable
        }

        /// Validates transport and header safety before sending or persisting credentials.
        private static func validate(address: String, token: String) throws -> (url: URL, token: String) {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parts = URLComponents(string: trimmed), let url = parts.url,
                  let host = parts.host?.lowercased(), !host.isEmpty,
                  parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
                  parts.port == nil || (1 ... 65535).contains(parts.port!)
            else { throw InvalidConfiguration(message: "Enter a backend address without credentials, a query, or a fragment.") }
            let octets = host.split(separator: ".", omittingEmptySubsequences: false)
            let ipv4Loopback = octets.count == 4 && octets.first == "127" && octets.allSatisfy { UInt8($0) != nil }
            let loopback = host == "localhost" || host == "[::1]" || host == "::1" || ipv4Loopback
            guard parts.scheme?.lowercased() == "https" || (parts.scheme?.lowercased() == "http" && loopback) else {
                throw InvalidConfiguration(message: "Use HTTPS for a remote backend, or HTTP with a loopback address on this Mac.")
            }
            guard !token.isEmpty, token.utf8.allSatisfy({ (33 ... 126).contains($0) }) else {
                throw InvalidConfiguration(message: "Enter the connection token configured on your backend, without spaces.")
            }
            return (url, token)
        }

        /// A user-facing validation failure that never includes the supplied values.
        private struct InvalidConfiguration: Error {
            /// The corrective instruction shown in Settings and the main window.
            let message: String
        }
    }

    /// Prevents redirect responses from forwarding the connection token to another address.
    private final class ConnectionRedirectPolicy: NSObject, URLSessionTaskDelegate {
        /// Refuses all redirects; the configured address must be the final backend address.
        func urlSession(
            _: URLSession, task _: URLSessionTask,
            willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest _: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void,
        ) {
            completionHandler(nil)
        }
    }
#endif
