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
        func send(_ path: String, method: String = "GET", configuration: (url: URL, token: String), body: Data? = nil) async throws -> Data {
            var request = URLRequest(url: configuration.url.appendingPathComponent(path))
            request.httpMethod = method
            request.httpBody = body
            if body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            request.timeoutInterval = 15
            request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw Failure.unavailable }
            switch response.statusCode {
            case 200 ... 299: return data
            case 401, 403:
                let problem = try? JSONDecoder().decode(ConnectionProblem.self, from: data)
                if problem?.code == .kiteSignInRequired {
                    throw Failure.signedOut
                }
                throw Failure.configuration
            case 503:
                let problem = try? JSONDecoder().decode(ConnectionProblem.self, from: data)
                if problem?.code == .backendNotConfigured {
                    throw Failure.backendConfiguration
                }
                throw Failure.unavailable
            default: throw Failure.unavailable
            }
        }

        /// Shared failure categories for backend requests and authentication operations.
        enum Failure: Error {
            /// App authorization was rejected.
            case configuration
            /// The authorized backend has no valid Kite session.
            case signedOut
            /// Kite credentials have not been configured.
            case backendConfiguration
            /// Browser handoff could not begin.
            case failed
            /// A read or connection can be retried.
            case unavailable
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
