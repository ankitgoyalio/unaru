//
//  MutualFundHoldingsView.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Mutual fund retrieval, loading and failure remain visible independently of securities.
    struct MutualFundHoldingsView: View {
        @EnvironmentObject private var connection: BackendConnection
        /// The connection's memory-only source state.
        @ObservedObject var store: PortfolioStore
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mutual Fund Holdings").font(.title2).accessibilityAddTraits(.isHeader)
                if store.mutualFundsLoading {
                    ProgressView("Loading mutual fund holdings…")
                }
                if store.mutualFundsFailed {
                    Text("Couldn’t refresh mutual fund holdings").font(.headline)
                    if store.mutualFundsSnapshot != nil {
                        Text("Stale mutual funds — showing the previous retrieval.")
                    }
                    Button("Retry Mutual Funds") { connection.refreshPortfolio(source: .mutualFunds) }
                }
                if let snapshot = store.mutualFundsSnapshot {
                    Text("Retrieved \(snapshot.retrievedAt.formatted(date: .abbreviated, time: .standard))")
                        .accessibilityIdentifier("Mutual funds retrieval time")
                    Text("NAV dates refer to each fund’s available valuation, not retrieval time.")
                        .foregroundStyle(.secondary)
                    if snapshot.holdings.isEmpty {
                        ContentUnavailableView("No Mutual Fund Holdings", systemImage: "tray",
                                               description: Text("Kite returned an empty mutual fund holdings source."))
                    } else {
                        Text("\(snapshot.holdings.count) mutual fund holdings")
                    }
                }
            }
        }
    }

    /// Inspection preserves exact fractional source precision rather than currency display rounding.
    func mutualFundDecimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
#endif
