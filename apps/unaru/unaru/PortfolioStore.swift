//
//  PortfolioStore.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Combine
    import Foundation
    import Shared

    /// Memory-only holdings sources shared across windows, scoped to the connection's authority.
    @MainActor
    final class PortfolioStore: ObservableObject {
        /// Last successful response, retained visibly stale after a failed refresh.
        @Published private(set) var snapshot: SecuritiesHoldings?
        /// Initial and subsequent reads use the same visible progress state.
        @Published private(set) var isLoading = false
        /// A failed source is different from a successful empty source.
        @Published private(set) var failed = false
        /// Last successful mutual fund response, retained visibly stale on source failure.
        @Published private(set) var mutualFundsSnapshot: MutualFundHoldings?
        /// Mutual funds load independently from securities.
        @Published private(set) var mutualFundsLoading = false
        /// A mutual fund failure does not hide successful securities.
        @Published private(set) var mutualFundsFailed = false
        /// Separate task permits either source to complete first.
        private var mutualFundsTask: Task<Void, Never>?
        /// Mutual fund retries and responses have their own refresh ordering.
        private var mutualFundsRevision = 0
        /// Makes cancellation safe even when a transport resumes after cancellation.
        private var revision = 0
        /// Only this store owns portfolio request lifetime; closing a window does not log out.
        private var task: Task<Void, Never>?

        /// Discards all account-bound data before any new account can be presented.
        func clear() {
            revision += 1
            mutualFundsRevision += 1
            task?.cancel()
            mutualFundsTask?.cancel()
            mutualFundsSnapshot = nil
            mutualFundsLoading = false
            mutualFundsFailed = false
            snapshot = nil
            isLoading = false
            failed = false
        }

        /// The two independent holdings sources supported by a source-specific retry.
        enum Source: Equatable {
            /// Ordinary securities holdings, separate from trading positions.
            case securities
            /// Fractional mutual fund holdings.
            case mutualFunds
        }

        /// Opening Portfolio and Refresh request both sources, each with its own lifetime.
        func refresh(source: Source? = nil, transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            if source != .mutualFunds {
                refreshSecurities(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
            }
            if source != .securities {
                refreshMutualFunds(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
            }
        }

        /// A securities retry leaves the mutual fund source and in-flight request untouched.
        func refreshSecurities(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
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
                    let data = try await transport.send("portfolio/holdings", configuration: configuration)
                    let result = try JSONDecoder().decode(SecuritiesHoldings.self, from: data)
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

        /// A mutual fund retry leaves securities visible and does not supersede their request.
        func refreshMutualFunds(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            mutualFundsRevision += 1
            let currentRevision = mutualFundsRevision
            mutualFundsTask?.cancel()
            mutualFundsLoading = true
            mutualFundsFailed = false
            mutualFundsTask = Task {
                defer {
                    if currentRevision == mutualFundsRevision {
                        mutualFundsLoading = false
                    }
                }
                do {
                    let data = try await transport.send("portfolio/mutual-funds", configuration: configuration)
                    let result = try JSONDecoder().decode(MutualFundHoldings.self, from: data)
                    guard !Task.isCancelled, mutualFundsRevision == currentRevision else { return }
                    mutualFundsSnapshot = result
                } catch {
                    guard !Task.isCancelled, mutualFundsRevision == currentRevision else { return }
                    switch error {
                    case BackendTransport.Failure.signedOut: authorityFailure(.signedOut)
                    case BackendTransport.Failure.configuration: authorityFailure(.configuration)
                    default: mutualFundsFailed = true
                    }
                }
            }
        }

        deinit {
            task?.cancel()
            mutualFundsTask?.cancel()
        }
    }
#endif
