//
//  PositionsStore.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Combine
    import Foundation
    import Shared

    /// One memory-only source shared across windows, scoped to the connection's authority.
    @MainActor
    final class PositionsStore: ObservableObject {
        /// Last successful response, retained visibly stale after a failed refresh.
        @Published private(set) var snapshot: NetPositions?
        /// Initial and subsequent reads use the same visible progress state.
        @Published private(set) var isLoading = false
        /// A failed source is different from a successful empty source.
        @Published private(set) var failed = false
        /// This source retains its own cancellation and response ordering.
        private let request = SourceRequest()

        /// Discards all account-bound data before any new account can be presented.
        func clear() {
            request.cancel()
            snapshot = nil
            isLoading = false
            failed = false
        }

        /// Uses the existing authenticated transport, rejecting both obsolete success and failure.
        func refresh(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            isLoading = true
            failed = false
            request.load("portfolio/positions", transport: transport, configuration: configuration, authorityFailure: authorityFailure,
                         receive: { (result: NetPositions) in self.snapshot = result },
                         failure: { self.failed = true }, completion: { self.isLoading = false })
        }
    }
#endif
