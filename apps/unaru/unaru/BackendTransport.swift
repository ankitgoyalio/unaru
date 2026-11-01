//
//  BackendTransport.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import Foundation
    import Shared

    /// Credential-bearing HTTP with transport validation and redirects disabled.
    @MainActor
    final class BackendTransport {
        /// An ephemeral session that never follows a credential-bearing redirect.
        private let session = URLSession(configuration: .ephemeral, delegate: ConnectionRedirectPolicy(), delegateQueue: nil)

        /// Sends credentials only in headers and refuses redirects through the shared transport.
        func send(_ path: String, method: String = "GET", configuration: (url: URL, token: String), body: Data? = nil, localProof: String? = nil) async throws -> Data {
            var request = URLRequest(url: configuration.url.appendingPathComponent(path))
            request.httpMethod = method
            request.httpBody = body
            if body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let localProof {
                request.setValue(localProof, forHTTPHeaderField: "X-Unaru-Local-Pairing")
            }
            request.timeoutInterval = 15
            request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw BackendConnection.LoginFailure.unavailable }
            switch response.statusCode {
            case 200 ... 299: return data
            case 401, 403:
                let problem = try? JSONDecoder().decode(ConnectionProblem.self, from: data)
                if problem?.code == .kiteSignInRequired {
                    throw BackendConnection.LoginFailure.signedOut
                }
                throw BackendConnection.LoginFailure.configuration
            case 503:
                let problem = try? JSONDecoder().decode(ConnectionProblem.self, from: data)
                if problem?.code == .backendNotConfigured {
                    throw BackendConnection.LoginFailure.backendConfiguration
                }
                throw BackendConnection.LoginFailure.unavailable
            default: throw BackendConnection.LoginFailure.unavailable
            }
        }

        /// Validates transport and header safety before sending or persisting credentials.
        static func validate(address: String, token: String) throws -> (url: URL, token: String) {
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
        struct InvalidConfiguration: Error {
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
