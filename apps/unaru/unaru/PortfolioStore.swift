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
        /// Backend-established overlap restrictions survive source replacement until authoritative resolution.
        private var overlappingInstruments: Set<String> = []
        /// Indexed source-local restrictions avoid searching all rows for each table cell.
        private var overlappingRows: Set<String> = []
        /// A retained source snapshot is not evidence of success in the current refresh.
        private var securitiesCurrent = false
        /// Mutual funds must also succeed in this refresh before requesting totals.
        private var mutualFundsCurrent = false
        /// Combined analysis has a lifetime separate from both contributing sources.
        private let performanceRequest = SourceRequest()
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
        /// Independent source lifetimes preserve successful peers during retry.
        private let securitiesRequest = SourceRequest()
        /// Mutual funds can complete before or after securities.
        private let mutualFundsRequest = SourceRequest()

        /// Discards all account-bound data before any new account can be presented.
        func clear() {
            invalidatePerformance()
            performanceRows = [:]
            performanceSources = nil
            overlappingInstruments = []
            overlappingRows = []
            securitiesCurrent = false
            mutualFundsCurrent = false
            securitiesRequest.cancel()
            mutualFundsRequest.cancel()
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
            isLoading = true
            failed = false
            securitiesRequest.load("portfolio/holdings", transport: transport, configuration: configuration, authorityFailure: authorityFailure,
                                   receive: { (result: SecuritiesHoldings) in
                                       self.snapshot = result
                                       self.updateOverlapRows()
                                       self.securitiesCurrent = true
                                   }, failure: { self.failed = true }, completion: {
                                       self.isLoading = false
                                       self.refreshPerformance(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
                                   })
        }

        /// A mutual fund retry leaves securities visible and does not supersede their request.
        func refreshMutualFunds(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            invalidatePerformance()
            mutualFundsCurrent = false
            mutualFundsLoading = true
            mutualFundsFailed = false
            mutualFundsRequest.load("portfolio/mutual-funds", transport: transport, configuration: configuration, authorityFailure: authorityFailure,
                                    receive: { (result: MutualFundHoldings) in
                                        self.mutualFundsSnapshot = result
                                        self.updateOverlapRows()
                                        self.mutualFundsCurrent = true
                                    }, failure: { self.mutualFundsFailed = true }, completion: {
                                        self.mutualFundsLoading = false
                                        self.refreshPerformance(transport: transport, configuration: configuration, authorityFailure: authorityFailure)
                                    })
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
            if matches, let row = performanceRows[source.qualifiedID(id)] {
                return row
            }
            guard overlappingRows.contains(source.qualifiedID(id)) else { return nil }
            return PortfolioHoldingPerformance(source: source, sourceRowID: id,
                                               values: HoldingPerformance(quantity: nil, investedCost: nil, currentValue: nil, gain: nil, returnPercent: nil),
                                               overlapsSources: true)
        }

        /// A changed source row ID does not erase a backend-established instrument restriction.
        private func updateOverlapRows() {
            overlappingRows = Set((snapshot?.holdings ?? []).filter { overlappingInstruments.contains($0.isin) }
                .map { PortfolioHoldingPerformance.Source.securities.qualifiedID($0.id) }
                + (mutualFundsSnapshot?.holdings ?? []).filter { overlappingInstruments.contains($0.symbol) }
                .map { PortfolioHoldingPerformance.Source.mutualFunds.qualifiedID($0.id) })
        }

        /// Invalidates the aggregate before any contributing source begins a new read.
        private func invalidatePerformance() {
            performanceRequest.cancel()
            performance = nil
            performanceFailed = false
        }

        /// Sends read identities only; all financial calculations remain on the backend.
        private func refreshPerformance(transport: BackendTransport, configuration: (url: URL, token: String), authorityFailure: @escaping @MainActor (BackendTransport.Failure) -> Void) {
            guard securitiesCurrent, mutualFundsCurrent, !isLoading, !mutualFundsLoading,
                  let securitiesID = snapshot?.readID, let fundsID = mutualFundsSnapshot?.readID else { return }
            let sources = PortfolioPerformanceRequest(securitiesReadID: securitiesID, mutualFundsReadID: fundsID)
            // The request contains only two strings; encoding cannot fail for these values.
            guard let body = try? JSONEncoder().encode(sources) else { performanceFailed = true; return }
            performanceRequest.load("portfolio/performance", method: "POST", body: body, transport: transport, configuration: configuration,
                                    authorityFailure: authorityFailure, receive: { (result: PortfolioPerformance) in
                                        guard result.sources.securitiesReadID == securitiesID, result.sources.mutualFundsReadID == fundsID else { return }
                                        self.performanceRows = Dictionary(uniqueKeysWithValues: (result.rows ?? []).map { ($0.id, $0) })
                                        self.performanceSources = result.sources
                                        if result.rows != nil {
                                            self.overlappingInstruments = Set((self.snapshot?.holdings ?? []).filter {
                                                self.performanceRows[PortfolioHoldingPerformance.Source.securities.qualifiedID($0.id)]?.overlapsSources == true
                                            }.map(\.isin) + (self.mutualFundsSnapshot?.holdings ?? []).filter {
                                                self.performanceRows[PortfolioHoldingPerformance.Source.mutualFunds.qualifiedID($0.id)]?.overlapsSources == true
                                            }.map(\.symbol))
                                            self.updateOverlapRows()
                                        }
                                        self.performance = result
                                    }, failure: { self.performanceFailed = true })
        }
    }
#endif
