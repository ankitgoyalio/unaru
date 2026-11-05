//
//  SourceRequest.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation

    /// Owns one independent authenticated source lifetime, rejecting obsolete success and failure.
    @MainActor
    final class SourceRequest {
        /// Cancellation alone cannot reject a transport that resumes after cancellation.
        private var revision = 0
        /// Each source owns its task; refreshing a peer never cancels it.
        private var task: Task<Void, Never>?

        /// Invalidates callbacks before cancelling the transport work.
        func cancel() {
            revision += 1
            task?.cancel()
            task = nil
        }

        /// Decodes the credential-free response and dispatches only current source or authority outcomes.
        func load<Response: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil,
                                                  transport: BackendTransport, configuration: (url: URL, token: String),
                                                  authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void,
                                                  receive: @escaping @MainActor (Response) -> Void,
                                                  failure: @escaping @MainActor () -> Void,
                                                  completion: @escaping @MainActor () -> Void = {})
        {
            cancel()
            let currentRevision = revision
            task = Task {
                defer {
                    if currentRevision == revision {
                        completion()
                    }
                }
                do {
                    let data = try await transport.send(path, method: method, configuration: configuration, body: body)
                    let result = try JSONDecoder().decode(Response.self, from: data)
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    receive(result)
                } catch {
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    switch error {
                    case BackendTransport.Failure.signedOut: authorityFailure(.signedOut)
                    case BackendTransport.Failure.configuration: authorityFailure(.configuration)
                    default: failure()
                    }
                }
            }
        }

        deinit { task?.cancel() }
    }
#endif
