//
//  BackendConnection.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
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
            /// The user must correct connection settings.
            case configurationError(String)
            /// The server configuration needs repair, rather than Kite reauthentication.
            case backendError
            /// A temporary connection or server failure permits retry.
            case unavailable
        }

        /// The state presented by every main window.
        @Published private(set) var phase: Phase = .setup
        /// The nonsecret address loaded for Settings.
        @Published private(set) var address = ""
        /// Storage for the address and Keychain credential.
        private let storage = ConnectionStorage()
        /// The current request, cancelled whenever configuration changes.
        private var task: Task<Void, Never>?
        /// A monotonically changing identifier that rejects obsolete results.
        private var revision = 0
        /// The current validated connection information.
        private var configuration: (url: URL, token: String)?
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

        /// Loads the token directly from Keychain for the secure Settings field.
        func savedToken() throws -> String {
            try storage.readToken()
        }

        /// Invalidates prior results, saves valid settings, and verifies the new connection.
        @discardableResult
        func save(address: String, token: String) -> Bool {
            revision += 1
            task?.cancel()
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
            guard let configuration else { return }
            revision += 1
            let currentRevision = revision
            task?.cancel()
            phase = .checking
            task = Task {
                var request = URLRequest(url: configuration.url.appendingPathComponent("session"))
                request.timeoutInterval = 15
                request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                do {
                    let (data, response) = try await session.data(for: request)
                    guard !Task.isCancelled, currentRevision == revision else { return }
                    guard let response = response as? HTTPURLResponse else {
                        phase = .unavailable
                        return
                    }
                    switch response.statusCode {
                    case 200:
                        let status = try JSONDecoder().decode(SessionStatus.self, from: data)
                        switch status.state {
                        case .signedOut: phase = .signedOut
                        }
                    case 401, 403:
                        phase = .configurationError("The backend rejected the connection token. Check the token in Settings.")
                    case 503:
                        let problem = try? JSONDecoder().decode(ConnectionProblem.self, from: data)
                        phase = problem?.code == .backendNotConfigured ? .backendError : .unavailable
                    default:
                        phase = .unavailable
                    }
                } catch {
                    guard !Task.isCancelled, currentRevision == revision else { return }
                    phase = .unavailable
                }
            }
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
