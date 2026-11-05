//
//  PositionsView.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Shared
    import SwiftUI

    /// Supporting broker exposure, with closed net rows grouped separately.
    struct PositionsView: View {
        @EnvironmentObject private var connection: BackendConnection
        /// Source state shared by every account window.
        @ObservedObject var store: PositionsStore
        /// One selection per group follows native table keyboard navigation.
        @State private var currentSelection: TradingPosition.ID?
        /// Closed rows can be inspected without implying current exposure.
        @State private var closedSelection: TradingPosition.ID?
        /// The focused selection determines the Return action.
        @State private var inspected: TradingPosition?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Positions").font(.largeTitle).accessibilityAddTraits(.isHeader)
                Text("Trading P&L is separate from holdings returns.").foregroundStyle(.secondary)
                Text("Kite net positions only. Delivery purchases remain here until reported as holdings.")
                    .foregroundStyle(.secondary)
                if store.isLoading {
                    ProgressView("Loading positions…")
                }
                if store.failed {
                    Text("Couldn’t refresh positions").font(.headline)
                    if store.snapshot != nil {
                        Text("Stale positions — showing the previous retrieval.")
                    }
                    Button("Retry Positions") { connection.refreshPositions() }
                }
                if let snapshot = store.snapshot {
                    Text("Retrieved \(snapshot.retrievedAt.formatted(date: .abbreviated, time: .standard))")
                        .accessibilityIdentifier("Positions retrieval time")
                    Text("Price valuation date unavailable").foregroundStyle(.secondary)
                    if snapshot.positions.isEmpty {
                        ContentUnavailableView("No Positions", systemImage: "tray",
                                               description: Text("Kite returned an empty net positions source."))
                    } else {
                        group("Current Net Positions", rows: snapshot.positions.filter { $0.state == .current },
                              selection: $currentSelection, accessibility: "Current net positions")
                        group("Closed Positions", rows: snapshot.positions.filter { $0.state == .closed },
                              selection: $closedSelection, accessibility: "Closed positions")
                        Button("Inspect Position") { inspect(currentSelection ?? closedSelection) }
                            .disabled(currentSelection == nil && closedSelection == nil)
                            .keyboardShortcut(.return, modifiers: [])
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sheet(item: $inspected) { position in PositionInspection(store: store, position: position) }
            .onChange(of: currentSelection) { _, value in
                if value != nil {
                    closedSelection = nil
                }
            }
            .onChange(of: closedSelection) { _, value in
                if value != nil {
                    currentSelection = nil
                }
            }
            .onReceive(store.$snapshot) { _ in
                currentSelection = nil
                closedSelection = nil
                inspected = nil
            }
            .onAppear { connection.refreshPositions() }
        }

        /// Each native table has its own selection and a keyboard-accessible inspection action.
        private func group(_ title: String, rows: [TradingPosition], selection: Binding<String?>, accessibility: String) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if rows.isEmpty {
                    Text(title == "Closed Positions" ? "No closed positions returned" : "No current net positions")
                        .foregroundStyle(.secondary)
                } else {
                    Table(rows, selection: selection) {
                        TableColumn("Instrument") { row in
                            VStack(alignment: .leading) {
                                Text(row.symbol)
                                Text(row.exchange).foregroundStyle(.secondary)
                            }
                        }
                        TableColumn("Product", value: \.product)
                        TableColumn("Signed Quantity") { row in Text(String(row.quantity)) }
                        TableColumn("Last Price") { row in Text(usablePrice(row.lastPrice)) }
                        TableColumn("Realised P&L") { row in Text(tradingPnL(row.realised)) }
                        TableColumn("Unrealised P&L") { row in Text(tradingPnL(row.unrealised)) }
                    }
                    .frame(height: 150)
                    .accessibilityLabel(accessibility)
                    .contextMenu(forSelectionType: String.self) { identifiers in
                        Button("Inspect Position") { inspect(identifiers.first) }
                    } primaryAction: { identifiers in inspect(identifiers.first) }
                }
            }
        }

        /// Resolves against the current snapshot instead of a stale selected row.
        private func inspect(_ id: String?) {
            inspected = store.snapshot?.positions.first { $0.id == id }
        }
    }
#endif
