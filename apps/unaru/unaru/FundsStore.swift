//
//  FundsStore.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Combine
    import Foundation
    import Shared

    /// One independent memory-only funds source shared across windows, scoped to the connection's authority.
    @MainActor
    final class FundsStore: ObservableObject {
        /// Last successful response, retained visibly stale after a failed refresh.
        @Published private(set) var snapshot: TradingFunds?
        /// Initial and subsequent reads use the same visible progress state.
        @Published private(set) var isLoading = false
        /// A failed source is different from a successful empty source.
        @Published private(set) var failed = false
        /// Makes cancellation safe even when a transport resumes after cancellation.
        private var revision = 0
        /// Only this store owns funds request lifetime; closing a window does not log out.
        private var task: Task<Void, Never>?

        /// Discards all account-bound data before any new account can be presented.
        func clear() {
            revision += 1
            task?.cancel()
            snapshot = nil
            isLoading = false
            failed = false
        }

        /// Uses the existing authenticated transport, rejecting both obsolete success and failure.
        func refresh(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            revision += 1
            let currentRevision = revision
            task?.cancel()
            isLoading = true
            failed = false
            task = Task {
                defer {
                    if currentRevision == revision {
                        isLoading = false
                    }
                }
                do {
                    let data = try await transport.send("portfolio/funds", configuration: configuration)
                    let result = try JSONDecoder().decode(TradingFunds.self, from: data)
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    snapshot = result
                } catch {
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    switch error {
                    case BackendTransport.Failure.signedOut: authorityFailure(.signedOut)
                    case BackendTransport.Failure.configuration: authorityFailure(.configuration)
                    default: failed = true
                    }
                }
            }
        }

        deinit { task?.cancel() }
    }
#endif
