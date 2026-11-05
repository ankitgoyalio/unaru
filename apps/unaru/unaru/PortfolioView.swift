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

    /// Native overview and source status keep investment holdings separate from supporting destinations.
    struct PortfolioView: View {
        @EnvironmentObject private var connection: BackendConnection
        /// Window-local selection in the Portfolio sidebar hierarchy.
        @Binding var destination: PortfolioDestination?
        /// Shared memory-only source state from the authenticated connection.
        @ObservedObject var store: PortfolioStore
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(destination == .holdings ? "Holdings" : "Portfolio Overview")
                        .font(.largeTitle).accessibilityAddTraits(.isHeader)
                    Text("Holdings returned by your connected Kite account. Coverage may be incomplete.")
                        .foregroundStyle(.secondary)
                    if destination == .portfolio {
                        PortfolioPerformanceView(store: store)
                        if let allocation = store.performance?.allocation {
                            PortfolioAllocationView(allocation: allocation)
                        }
                    }
                    if destination == .holdings {
                        HoldingsBrowser(store: store)
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
                        Text(snapshot.valuationDate.map { "Price valuation date: \($0)" } ?? "Price valuation date unavailable")
                            .foregroundStyle(.secondary)
                        if snapshot.holdings.isEmpty {
                            ContentUnavailableView("No Securities Holdings", systemImage: "tray",
                                                   description: Text("Kite returned an empty securities holdings source."))
                        } else {
                            Text("\(snapshot.holdings.count) securities holdings")
                        }
                    }
                    Divider()
                    MutualFundHoldingsView(store: store)
                    if destination != .holdings {
                        Button("View Holdings") { destination = .holdings }
                    }
                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .accessibilityLabel("Portfolio content")
            .onAppear { connection.refreshPortfolio() }
            .onChange(of: destination) { _, newValue in
                if newValue == .portfolio {
                    connection.refreshPortfolio()
                }
            }
        }
    }
#endif
