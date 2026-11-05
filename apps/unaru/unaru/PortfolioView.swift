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
        /// Opens the source overview and refreshes securities holdings.
        case portfolio
        /// Lists every security returned by the source for inspection.
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

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(destination == .holdings ? "Securities Holdings" : "Portfolio Overview")
                    .font(.largeTitle).accessibilityAddTraits(.isHeader)
                Text("Securities reported by Kite. Mutual funds are not included in this source.")
                    .foregroundStyle(.secondary)
                if store.isLoading {
                    ProgressView("Loading securities holdings…")
                }
                if store.failed {
                    Text("Couldn’t refresh securities holdings").font(.headline)
                    if store.snapshot != nil {
                        Text("Stale holdings — showing the previous retrieval.")
                    }
                    Button("Retry") { connection.refreshPortfolio() }
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
                                TableColumn("Symbol", value: \.symbol)
                                TableColumn("Exchange", value: \.exchange)
                                TableColumn("Quantity (Kite)") { row in Text(String(row.quantity)) }
                                TableColumn("Market Price") { row in Text(usablePrice(row.lastPrice)) }
                            }
                            .frame(height: 360)
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
                if destination != .holdings {
                    Button("View Holdings") { destination = .holdings }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sheet(item: $inspected) { holding in HoldingInspection(holding: holding) }
            .onReceive(store.$snapshot) { _ in
                selection = nil
                inspected = nil
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
