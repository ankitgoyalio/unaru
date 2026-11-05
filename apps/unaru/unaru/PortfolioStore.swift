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
        /// Backend-calculated totals for exactly the successful sources in the current refresh.
        @Published private(set) var performance: PortfolioPerformance?
        /// An aggregate request can fail independently of successful source rows.
        @Published private(set) var performanceFailed = false
        /// Final per-row results are indexed once, avoiding searches for every table cell.
        private var performanceRows: [String: PortfolioHoldingPerformance] = [:]
        /// Retained projections apply only to their exact source retrievals, including stale inspection.
        private var performanceSources: PortfolioPerformanceRequest?
        /// A retained source snapshot is not evidence of success in the current refresh.
        private var securitiesCurrent = false
        /// Mutual funds must also succeed in this refresh before requesting totals.
        private var mutualFundsCurrent = false
        /// Aggregate responses must not outlive their contributing source requests.
        private var performanceRevision = 0
        /// Separate lifetime for the credential-free aggregate read.
        private var performanceTask: Task<Void, Never>?
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
            invalidatePerformance()
            performanceRows = [:]
            performanceSources = nil
            securitiesCurrent = false
            mutualFundsCurrent = false
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
            if source == nil {
                securitiesCurrent = false
                mutualFundsCurrent = false
            }
            if source != .mutualFunds {
                refreshSecurities(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
            }
            if source != .securities {
                refreshMutualFunds(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
            }
        }

        /// A securities retry leaves the mutual fund source and in-flight request untouched.
        func refreshSecurities(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            invalidatePerformance()
            securitiesCurrent = false
            revision += 1
            let currentRevision = revision
            task?.cancel()
            isLoading = true
            failed = false
            task = Task {
                defer {
                    if currentRevision == revision {
                        isLoading = false
                        refreshPerformance(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
                    }
                }
                do {
                    let data = try await transport.send("portfolio/holdings", configuration: configuration)
                    let result = try JSONDecoder().decode(SecuritiesHoldings.self, from: data)
                    guard !Task.isCancelled, revision == currentRevision else { return }
                    snapshot = result
                    securitiesCurrent = true
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
            invalidatePerformance()
            mutualFundsCurrent = false
            mutualFundsRevision += 1
            let currentRevision = mutualFundsRevision
            mutualFundsTask?.cancel()
            mutualFundsLoading = true
            mutualFundsFailed = false
            mutualFundsTask = Task {
                defer {
                    if currentRevision == mutualFundsRevision {
                        mutualFundsLoading = false
                        refreshPerformance(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
                    }
                }
                do {
                    let data = try await transport.send("portfolio/mutual-funds", configuration: configuration)
                    let result = try JSONDecoder().decode(MutualFundHoldings.self, from: data)
                    guard !Task.isCancelled, mutualFundsRevision == currentRevision else { return }
                    mutualFundsSnapshot = result
                    mutualFundsCurrent = true
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

        /// Final combined eligibility takes precedence over a source-only valuation.
        func values(for row: SecurityHolding) -> HoldingPerformance? {
            analyzedRow(source: .securities, id: row.id)?.values ?? row.performance
        }

        /// Fund rows use the same authoritative projection as combined performance.
        func values(for row: MutualFundHolding) -> HoldingPerformance? {
            analyzedRow(source: .mutualFunds, id: row.id)?.values ?? row.performance
        }

        /// Opaque source IDs prevent a retained projection from attaching to a replacement row.
        func analyzedRow(source: PortfolioHoldingPerformance.Source, id: String) -> PortfolioHoldingPerformance? {
            let matches = source == .securities ? performanceSources?.securitiesReadID == snapshot?.readID : performanceSources?.mutualFundsReadID == mutualFundsSnapshot?.readID
            return matches ? performanceRows[source.rawValue + ":" + id] : nil
        }

        /// Invalidates the aggregate before any contributing source begins a new read.
        private func invalidatePerformance() {
            performanceRevision += 1
            performanceTask?.cancel()
            performance = nil
            performanceFailed = false
        }

        /// Sends read identities only; all financial calculations remain on the backend.
        private func refreshPerformance(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            guard securitiesCurrent, mutualFundsCurrent, !isLoading, !mutualFundsLoading,
                  let securitiesID = snapshot?.readID, let fundsID = mutualFundsSnapshot?.readID else { return }
            let currentRevision = performanceRevision
            let sources = PortfolioPerformanceRequest(securitiesReadID: securitiesID, mutualFundsReadID: fundsID)
            performanceTask = Task {
                do {
                    let body = try JSONEncoder().encode(sources)
                    let data = try await transport.send("portfolio/performance", method: "POST", configuration: configuration, body: body)
                    let result = try JSONDecoder().decode(PortfolioPerformance.self, from: data)
                    guard !Task.isCancelled, performanceRevision == currentRevision,
                          result.sources.securitiesReadID == securitiesID, result.sources.mutualFundsReadID == fundsID else { return }
                    performanceRows = Dictionary(uniqueKeysWithValues: (result.rows ?? []).map { ($0.id, $0) })
                    performanceSources = result.sources
                    performance = result
                } catch {
                    guard !Task.isCancelled, performanceRevision == currentRevision else { return }
                    switch error {
                    case BackendTransport.Failure.signedOut: authorityFailure(.signedOut)
                    case BackendTransport.Failure.configuration: authorityFailure(.configuration)
                    default: performanceFailed = true
                    }
                }
            }
        }

        deinit {
            performanceTask?.cancel()
            task?.cancel()
            mutualFundsTask?.cancel()
        }
    }
#endif
