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
            /// Waiting for the owner to approve this connection on the server.
            case pairing(String)
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
        /// Pending approval authority, revoked explicitly when Settings cancels or changes.
        private var pendingPairing: (id: String, configuration: (url: URL, token: String))?
        /// An ephemeral transport that refuses redirects carrying credentials.
        private let transport = BackendTransport()

        /// Restores configuration and verifies the server on launch.
        init() {
            address = storage.defaults.string(forKey: "backendAddress") ?? ""
            do {
                let token = try storage.readToken()
                guard !address.isEmpty, !token.isEmpty else { return }
                configuration = try BackendTransport.validate(address: address, token: token)
                verify()
            } catch is ConnectionStorage.StorageFailure {
                phase = .configurationError("The saved connection could not be read. Unlock Keychain, then open Settings to save your connection again.")
            } catch {
                phase = .configurationError("Open Settings to check the backend address and connect again.")
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

        /// Generates a credential and pairs this Mac without asking the user to copy a token.
        func connect(address: String) {
            cancelLogin()
            configuration = nil
            phase = .checking
            let currentRevision = revision
            task = Task {
                do {
                    let paired = try await BackendPairing(transport: transport).connect(address: address, savedCredential: address == self.address ? storage.readToken() : nil) { [weak self] status, configuration in
                        guard let self else { return }
                        guard revision == currentRevision, !Task.isCancelled else {
                            Task { _ = try? await transport.send("pairing/\(status.id)", method: "DELETE", configuration: configuration) }
                            return
                        }
                        pendingPairing = (status.id, configuration)
                        if !status.approved {
                            phase = .pairing(status.code)
                        }
                    }
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    try storage.save(address: paired.url.absoluteString, token: paired.token)
                    pendingPairing = nil
                    self.address = paired.url.absoluteString
                    configuration = paired
                    verify()
                } catch {
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    cancelPairing()
                    if let error = error as? BackendTransport.InvalidConfiguration {
                        phase = .configurationError(error.message)
                    } else {
                        phase = .configurationError("Connection could not complete. Check the backend, then choose Connect again. Pairing codes expire after five minutes.")
                    }
                }
            }
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
                    let data = try await transport.send("session", configuration: configuration)
                    guard !Task.isCancelled, currentRevision == revision else { return }
                    let status = try JSONDecoder().decode(SessionStatus.self, from: data)
                    switch status.state {
                    case .signedOut:
                        phase = .signedOut
                    case .signedIn:
                        let profileData = try await transport.send("profile", configuration: configuration)
                        let profile = try JSONDecoder().decode(AccountProfile.self, from: profileData)
                        guard !Task.isCancelled, currentRevision == revision else { return }
                        phase = .signedIn(profile)
                    }
                } catch {
                    guard !Task.isCancelled, currentRevision == revision else { return }
                    switch error {
                    case BackendTransport.Failure.signedOut: phase = .signedOut
                    case BackendTransport.Failure.configuration:
                        phase = .configurationError("This Mac is no longer authorized. Open Settings and choose Connect again.")
                    case BackendTransport.Failure.backendConfiguration: phase = .backendError
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
                    let data = try await transport.send("login", method: "POST", configuration: configuration)
                    let attempt = try JSONDecoder().decode(LoginAttempt.self, from: data)
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    activeAttempt = attempt
                    let url = attempt.browserURL
                    guard url.scheme == "https", url.host == "kite.zerodha.com", url.path == "/connect/login",
                          url.user == nil, url.password == nil, url.fragment == nil else { throw BackendTransport.Failure.failed }
                    #if DEBUG
                        if storage.service.contains(".uitests."), ProcessInfo.processInfo.environment["UNARU_TEST_BROWSER"] == "1" {
                            _ = try await transport.send("test/browser", method: "POST", configuration: configuration, body: data)
                        } else {
                            guard NSWorkspace.shared.open(url) else { throw BackendTransport.Failure.failed }
                        }
                    #else
                        guard NSWorkspace.shared.open(url) else { throw BackendTransport.Failure.failed }
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
            cancelPairing()
            let oldAttempt = activeAttempt
            activeAttempt = nil
            phase = configuration == nil ? .setup : .signedOut
            if let oldAttempt, let configuration {
                Task { _ = try? await transport.send("login/\(oldAttempt.id)", method: "DELETE", configuration: configuration) }
            }
        }

        /// Revokes a pending connection outside the cancelled request task.
        private func cancelPairing() {
            guard let pending = pendingPairing else { return }
            pendingPairing = nil
            Task { _ = try? await transport.send("pairing/\(pending.id)", method: "DELETE", configuration: pending.configuration) }
        }

        /// Polls only the authorized attempt until success, terminal failure, or a bounded deadline.
        private func observe(_ attempt: LoginAttempt, configuration: (url: URL, token: String), revision currentRevision: Int) async throws {
            let deadline = min(attempt.expiresAt, Date().addingTimeInterval(300))
            while Date() < deadline {
                let data = try await transport.send("login/\(attempt.id)", configuration: configuration)
                let result = try JSONDecoder().decode(LoginStatus.self, from: data)
                guard !Task.isCancelled, revision == currentRevision else { return }
                switch result.state {
                case .pending:
                    try await Task.sleep(for: .seconds(1))
                case .signedIn:
                    guard let profile = result.profile else { throw BackendTransport.Failure.failed }
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

        /// Maps login errors to an actionable state without displaying server diagnostics.
        private func showLoginError(_ error: any Error) {
            switch error {
            case BackendTransport.Failure.configuration:
                activeAttempt = nil
                phase = .configurationError("This Mac is no longer authorized. Open Settings and choose Connect again.")
            case BackendTransport.Failure.signedOut:
                activeAttempt = nil
                phase = .signedOut
            case BackendTransport.Failure.backendConfiguration:
                phase = .backendError
            case BackendTransport.Failure.failed:
                cancelLogin()
                phase = .loginFailed
            default:
                phase = .loginUnavailable
            }
        }
    }

#endif
