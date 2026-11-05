//
//  PortfolioView.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Shared
    import SwiftUI

    /// Only destinations with usable content are offered in the sidebar.
    enum PortfolioDestination: Hashable {
        /// Opens the source overview and refreshes both holdings sources.
        case portfolio
        /// Lists securities and mutual funds returned by Kite for inspection.
        case holdings
        /// Trading exposure stays separate from investment holdings.
        case positions
        /// Keeps trading balances separate from investment analysis.
        case funds
    }

    /// Native source status and navigation, with no combined investment total in this slice.
    struct PortfolioView: View {
        @EnvironmentObject private var connection: BackendConnection
        /// Window-local selection in the Portfolio sidebar hierarchy.
        @Binding var destination: PortfolioDestination?
        /// Shared memory-only source state from the authenticated connection.
        @ObservedObject var store: PortfolioStore
        @State private var selection: SecurityHolding.ID?
        @State private var inspected: SecurityHolding?

        @State private var mutualFundSelection: MutualFundHolding.ID?
        @State private var inspectedMutualFund: MutualFundHolding?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(destination == .holdings ? "Holdings" : "Portfolio Overview")
                        .font(.largeTitle).accessibilityAddTraits(.isHeader)
                    Text("Holdings returned by your connected Kite account. Coverage may be incomplete.")
                        .foregroundStyle(.secondary)
                    if destination == .portfolio {
                        PortfolioPerformanceView(store: store)
                    }
                    Text("Securities Holdings").font(.title2).accessibilityAddTraits(.isHeader)
                    if store.isLoading {
                        ProgressView("Loading securities holdings…")
                    }
                    if store.failed {
                        Text("Couldn’t refresh securities holdings").font(.headline)
                        if store.snapshot != nil {
                            Text("Stale holdings — showing the previous retrieval.")
                        }
                        Button("Retry") { connection.refreshPortfolio(source: .securities) }
                    }
                    if let snapshot = store.snapshot {
                        Text("Retrieved \(snapshot.retrievedAt.formatted(date: .abbreviated, time: .standard))")
                            .accessibilityIdentifier("Holdings retrieval time")
                        Text("Price valuation date unavailable")
                            .foregroundStyle(.secondary)
                        if snapshot.holdings.isEmpty {
                            ContentUnavailableView("No Securities Holdings", systemImage: "tray",
                                                   description: Text("Kite returned an empty securities holdings source."))
                        } else {
                            Text("\(snapshot.holdings.count) securities holdings")
                            if destination == .holdings {
                                Table(snapshot.holdings, selection: $selection) {
                                    TableColumn("Symbol", value: \.symbol).width(min: 80, ideal: 100)
                                    TableColumn("Exchange", value: \.exchange).width(55)
                                    TableColumn("Quantity") { row in Text(String(row.quantity)) }.width(70)
                                    TableColumn("Current Value") { row in Text(holdingMoney(store.values(for: row)?.currentValue)) }.width(min: 90, ideal: 110)
                                    TableColumn("Invested Cost") { row in Text(holdingMoney(store.values(for: row)?.investedCost)) }.width(min: 90, ideal: 110)
                                    TableColumn("Gain or Loss") { row in Text(holdingMoney(store.values(for: row)?.gain)) }.width(min: 90, ideal: 110)
                                    TableColumn("Return") { row in Text(holdingPercent(store.values(for: row)?.returnPercent)) }.width(75)
                                }
                                .frame(height: min(300, CGFloat(snapshot.holdings.count) * 28 + 40))
                                .accessibilityLabel("Securities holdings")
                                .contextMenu(forSelectionType: String.self) { identifiers in
                                    Button("Inspect Holding") { inspect(identifiers.first) }
                                } primaryAction: { identifiers in inspect(identifiers.first) }
                                Button("Inspect Holding") { inspect(selection) }
                                    .disabled(selection == nil)
                                    .keyboardShortcut(.return, modifiers: [])
                            }
                        }
                    }
                    Divider()
                    MutualFundHoldingsView(store: store, showsRows: destination == .holdings,
                                           selection: $mutualFundSelection, inspected: $inspectedMutualFund)
                    if destination != .holdings {
                        Button("View Holdings") { destination = .holdings }
                    }
                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .accessibilityLabel("Portfolio content")
            .sheet(item: $inspectedMutualFund) { holding in MutualFundInspection(store: store, holding: holding, analysis: store.analyzedRow(source: .mutualFunds, id: holding.id)) }
            .sheet(item: $inspected) { holding in HoldingInspection(store: store, holding: holding, analysis: store.analyzedRow(source: .securities, id: holding.id)) }
            .onReceive(store.$snapshot) { _ in
                selection = nil
                inspected = nil
            }
            .onReceive(store.$mutualFundsSnapshot) { _ in
                mutualFundSelection = nil
                inspectedMutualFund = nil
            }
            .onChange(of: selection) { _, value in
                if value != nil {
                    mutualFundSelection = nil
                }
            }
            .onChange(of: mutualFundSelection) { _, value in
                if value != nil {
                    selection = nil
                }
            }
            .onAppear { connection.refreshPortfolio() }
            .onChange(of: destination) { _, newValue in
                if newValue == .portfolio {
                    connection.refreshPortfolio()
                }
            }
        }

        private func inspect(_ id: String?) {
            inspected = store.snapshot?.holdings.first { $0.id == id }
        }
    }
#endif
