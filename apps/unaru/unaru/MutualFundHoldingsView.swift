//
//  MutualFundHoldingsView.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Separate source status and native table keep mutual fund dates and units inspectable.
    struct MutualFundHoldingsView: View {
        @EnvironmentObject private var connection: BackendConnection
        /// The connection's memory-only source state.
        @ObservedObject var store: PortfolioStore
        /// The overview shows source summaries; Holdings also shows the rows.
        let showsRows: Bool
        /// Selection stays local to this window.
        @Binding var selection: MutualFundHolding.ID?
        /// The exact broker row selected for inspection.
        @Binding var inspected: MutualFundHolding?

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
                        if showsRows {
                            Table(snapshot.holdings, selection: $selection) {
                                TableColumn("Fund", value: \.fund).width(120)
                                TableColumn("Units") { row in Text(mutualFundDecimal(row.quantity)) }.width(90)
                                TableColumn("Current Value") { row in Text(holdingMoney(store.values(for: row)?.currentValue)) }.width(85)
                                TableColumn("Invested Cost") { row in Text(holdingMoney(store.values(for: row)?.investedCost)) }.width(85)
                                TableColumn("Gain or Loss") { row in Text(holdingMoney(store.values(for: row)?.gain)) }.width(80)
                                TableColumn("Return") { row in Text(holdingPercent(store.values(for: row)?.returnPercent)) }.width(75)
                                TableColumn("NAV Date") { row in Text(row.navDate ?? "Unavailable") }.width(90)
                            }
                            .frame(height: min(260, CGFloat(snapshot.holdings.count) * 28 + 40))
                            .accessibilityLabel("Mutual fund holdings")
                            .contextMenu(forSelectionType: String.self) { identifiers in
                                Button("Inspect Mutual Fund") { inspect(identifiers.first) }
                            } primaryAction: { identifiers in inspect(identifiers.first) }
                            Button("Inspect Mutual Fund") { inspect(selection) }
                                .disabled(selection == nil)
                                .keyboardShortcut(.return, modifiers: [])
                        }
                    }
                }
            }
        }

        private func inspect(_ id: String?) {
            inspected = store.mutualFundsSnapshot?.holdings.first { $0.id == id }
        }
    }

    /// Inspection preserves exact fractional source precision rather than currency display rounding.
    func mutualFundDecimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
#endif
