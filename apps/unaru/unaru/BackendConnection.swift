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

    /// Owns the bundled backend and its currently verified Kite session.
    @MainActor
    final class BackendConnection: ObservableObject {
        /// The app-visible state of the current connection, never a cached identity.
        enum Phase: Equatable {
            /// The app is launching its embedded helper.
            case starting
            /// The embedded helper could not start or authorize the app.
            case startupFailed
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
            /// The server configuration needs repair, rather than Kite reauthentication.
            case backendError
            /// A temporary connection or server failure permits retry.
            case unavailable
            /// Saved authorization has not yet been durably removed.
            case logoutFailed
        }

        /// The state presented by every main window.
        @Published private(set) var phase: Phase = .starting {
            didSet {
                if case .signedIn = phase {} else {
                    isRefreshingAccount = false
                    accountRefreshFailed = false
                    saveRevision += 1
                    saveTask?.cancel()
                    isSavingSession = false
                    sessionSaveFailed = false
                }
                scheduleRevalidation()
            }
        }

        /// Local identity is already cleared while remote logout is being bounded.
        @Published private(set) var isLoggingOut = false
        /// A visible explanation retained until the next explicit sign-in.
        @Published private(set) var logoutUnconfirmed = false
        /// Verification cannot reattach old backend authority after local logout.
        private var requiresSignIn = false
        /// Durable logout is incomplete until the helper acknowledges secure removal.
        private var pendingLogout = BundledBackend.hasPendingLogout
        /// Refresh activity shared by sheets in every window.
        @Published private(set) var isRefreshingAccount = false
        /// A retryable failure never removes an already validated identity.
        @Published private(set) var accountRefreshFailed = false

        /// A storage failure does not remove the usable account.
        @Published private(set) var sessionSaveFailed = false
        /// Prevents duplicate save requests while keeping the account usable.
        @Published private(set) var isSavingSession = false
        /// Save completion cannot update a different login.
        private var saveRevision = 0
        /// Save recovery runs independently of profile refreshes.
        private var saveTask: Task<Void, Never>?

        /// Launches and stops the backend bundled inside this application.
        private let backend = BundledBackend()
        /// The current request, cancelled before restart or a new login.
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
        private let transport = BackendTransport()

        /// Starts the helper automatically without restoring external connection settings.
        init() {
            start()
        }

        /// Starts or restarts the helper, then waits for its private readiness signal.
        private func start() {
            cancelLogin()
            configuration = nil
            phase = .starting
            let currentRevision = revision
            task = Task {
                do {
                    let configuration = try backend.start()
                    try await backend.waitUntilReady()
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    self.configuration = configuration
                    if pendingLogout {
                        logOut()
                    } else if requiresSignIn {
                        phase = .signedOut
                    } else {
                        verify()
                    }
                } catch {
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    backend.stop()
                    phase = .startupFailed
                }
            }
        }

        /// Retries an available session or restarts the helper after startup/configuration failure.
        func retry() {
            if pendingLogout {
                if backend.isRunning, configuration != nil {
                    logOut()
                } else {
                    backend.stop()
                    start()
                }
                return
            }
            if !backend.isRunning || phase == .startupFailed || phase == .backendError {
                backend.stop()
                start()
            } else {
                verify()
            }
        }

        /// Reveals the app-owned Kite configuration directory.
        func openConfiguration() {
            backend.openConfiguration()
        }

        deinit {
            task?.cancel()
            revalidationTask?.cancel()
            saveTask?.cancel()
        }

        /// Rechecks provider authentication while the app remains open, including after sleep.
        private func scheduleRevalidation() {
            revalidationTask?.cancel()
            revalidationTask = nil
            guard case .signedIn = phase else { return }
            var interval: TimeInterval = 60
            #if DEBUG
                // Accelerate time only in isolated UI tests, never in production storage.
                if BundledBackend.isUITest,
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

        /// Rechecks the current helper without treating network failures as expired Kite authentication.
        func verify() {
            verify(preservingIdentity: false)
        }

        /// Refreshes the shared profile whenever a window opens its account sheet or retries.
        func refreshAccount() {
            guard case .signedIn = phase else { return }
            verify(preservingIdentity: true)
        }

        /// Keeps a validated footer stable during a background read, then applies the same error policy.
        private func verify(preservingIdentity: Bool) {
            guard !requiresSignIn, !isLoggingOut, let configuration else { return }
            revalidationTask?.cancel()
            revalidationTask = nil
            revision += 1
            let currentRevision = revision
            task?.cancel()
            isRefreshingAccount = preservingIdentity
            if !preservingIdentity {
                phase = .checking
            }
            let currentSaveRevision = saveRevision
            task = Task {
                defer {
                    if currentRevision == revision {
                        isRefreshingAccount = false
                    }
                }
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
                        accountRefreshFailed = false
                        if saveRevision == currentSaveRevision, !isSavingSession {
                            sessionSaveFailed = status.persistence == .saveFailed
                        }
                        phase = .signedIn(profile)
                    }
                } catch {
                    guard !Task.isCancelled, currentRevision == revision else { return }
                    switch error {
                    case BackendTransport.Failure.signedOut: phase = .signedOut
                    case BackendTransport.Failure.configuration:
                        phase = .startupFailed
                    case BackendTransport.Failure.backendConfiguration: phase = .backendError
                    default:
                        if preservingIdentity, case .signedIn = phase {
                            accountRefreshFailed = true
                            scheduleRevalidation()
                        } else {
                            phase = .unavailable
                        }
                    }
                }
            }
        }

        /// Saves current helper-held authority without another browser handoff.
        func retrySavingSession() {
            guard case .signedIn = phase, let configuration, !isSavingSession else { return }
            saveRevision += 1
            let currentSaveRevision = saveRevision
            isSavingSession = true
            saveTask = Task {
                defer {
                    if saveRevision == currentSaveRevision {
                        isSavingSession = false
                    }
                }
                do {
                    let data = try await transport.send("session/save", method: "POST", configuration: configuration)
                    let status = try JSONDecoder().decode(SessionStatus.self, from: data)
                    guard !Task.isCancelled, saveRevision == currentSaveRevision, case .signedIn = phase else { return }
                    sessionSaveFailed = status.state != .signedIn || status.persistence != .saved
                } catch {
                    guard !Task.isCancelled, saveRevision == currentSaveRevision, case .signedIn = phase else { return }
                    sessionSaveFailed = true
                }
            }
        }

        /// Creates an authorized attempt and opens the system's default browser.
        func signIn() {
            guard !isLoggingOut, let configuration, phase == .signedOut || phase == .loginFailed || (phase == .loginUnavailable && activeAttempt == nil) else { return }
            guard backend.isRunning else { start(); return }
            revision += 1
            let currentRevision = revision
            task?.cancel()
            activeAttempt = nil
            logoutUnconfirmed = false
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
                        if BundledBackend.isUITest, ProcessInfo.processInfo.environment["UNARU_TEST_BROWSER"] == "1" {
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

        /// Removes identity in every window synchronously, before contacting the backend.
        func logOut() {
            guard !isLoggingOut else { return }
            if !pendingLogout {
                guard case .signedIn = phase else { return }
            }
            pendingLogout = true
            revision += 1
            let currentRevision = revision
            task?.cancel()
            revalidationTask?.cancel()
            revalidationTask = nil
            activeAttempt = nil
            requiresSignIn = true
            isLoggingOut = true
            logoutUnconfirmed = false
            phase = .signedOut
            let oldConfiguration = configuration
            do {
                try BundledBackend.setLogoutPending(true)
            } catch {
                isLoggingOut = false
                phase = .logoutFailed
                return
            }
            task = Task {
                do {
                    guard let oldConfiguration else { throw BackendTransport.Failure.unavailable }
                    let data = try await transport.send("logout", method: "POST", configuration: oldConfiguration)
                    let result = try JSONDecoder().decode(LogoutResult.self, from: data)
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    try BundledBackend.setLogoutPending(false)
                    pendingLogout = false
                    logoutUnconfirmed = result.revocation != .confirmed
                    isLoggingOut = false
                } catch {
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    // A stopped helper may still have saved authorization. Keep logout
                    // pending and retry deletion before another sign-in or verification.
                    configuration = nil
                    backend.stop()
                    isLoggingOut = false
                    phase = .logoutFailed
                }
            }
        }

        /// Makes earlier browser/profile results obsolete immediately, then revokes the server attempt.
        func cancelLogin() {
            revision += 1
            task?.cancel()
            let oldAttempt = activeAttempt
            activeAttempt = nil
            phase = configuration == nil ? .starting : .signedOut
            if let oldAttempt, let configuration {
                Task { _ = try? await transport.send("login/\(oldAttempt.id)", method: "DELETE", configuration: configuration) }
            }
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
                    requiresSignIn = false
                    sessionSaveFailed = result.persistence == .saveFailed
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
            guard backend.isRunning else {
                activeAttempt = nil
                phase = .startupFailed
                return
            }
            switch error {
            case BackendTransport.Failure.configuration:
                activeAttempt = nil
                phase = .startupFailed
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
