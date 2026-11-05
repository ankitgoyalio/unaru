//
//  HoldingsBrowser.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Window-local search and inspection of every source-backed holding, including unavailable values.
    struct HoldingsBrowser: View {
        /// Shared memory-only snapshots remain owned by the authenticated connection.
        @ObservedObject var store: PortfolioStore
        /// Search is local to this window and never persisted.
        @State private var query = ""
        /// Supported source classifications; no security type is inferred from its trading symbol.
        @State private var investmentType = InvestmentType.all
        /// Initial ordering uses available current value from largest to smallest.
        @State private var sortBy = SortMeasure.currentValue
        @State private var direction = SortDirection.descending
        /// Selection and inspection always reference an exact source retrieval.
        @State private var selection: String?
        @State private var inspected: HoldingsRow?

        /// Concatenation retains every record without inferring relationships between sources.
        private var rows: [HoldingsRow] {
            let securities = store.snapshot.map { snapshot in
                snapshot.holdings.map { HoldingsRow(record: .security($0), retrievedAt: snapshot.retrievedAt, readID: snapshot.readID, valuationDate: snapshot.valuationDate) }
            } ?? []
            let funds = store.mutualFundsSnapshot.map { snapshot in
                snapshot.holdings.map { HoldingsRow(record: .mutualFund($0), retrievedAt: snapshot.retrievedAt, readID: snapshot.readID, valuationDate: $0.navDate) }
            } ?? []
            return securities + funds
        }

        /// Names and symbols match case and diacritics without changing the displayed provider text.
        private var visibleRows: [HoldingsRow] {
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return rows.filter { row in
                (investmentType == .all || (investmentType == .mutualFunds ? row.source == .mutualFunds : row.source == .securities)) &&
                    (search.isEmpty || row.name.localizedStandardContains(search) || row.symbol.localizedStandardContains(search))
            }.sorted(by: precedes)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name or symbol", text: $query)
                    .accessibilityLabel("Search holdings by name or symbol")
                HStack(spacing: 16) {
                    Picker("Investment Type", selection: $investmentType) {
                        ForEach(InvestmentType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityLabel("Investment Type")
                    Picker("Sort By", selection: $sortBy) {
                        ForEach(SortMeasure.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityLabel("Sort By")
                    Picker("Direction", selection: $direction) {
                        ForEach(SortDirection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityLabel("Sort Direction")
                }
                .pickerStyle(.menu)
                Text("Unknown types have no verified classification in the source.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Securities and mutual funds only. Positions and trading funds are separate.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Unavailable values sort last in either direction. Return uses unrealised return percentage.")
                    .font(.callout).foregroundStyle(.secondary)
                if !rows.isEmpty {
                    Text("\(visibleRows.count) of \(rows.count) holdings")
                    table.overlay {
                        if visibleRows.isEmpty {
                            ContentUnavailableView("No Matching Holdings", systemImage: "magnifyingglass",
                                                   description: Text("Change the search or investment type to see more holdings."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    if visibleRows.isEmpty {
                        Button("Clear Search and Filters") { query = ""; investmentType = .all }
                    }
                    Button("Inspect Holding") { inspect(selection) }
                        .disabled(selection == nil)
                        .keyboardShortcut(.return, modifiers: [])
                } else if store.snapshot != nil, store.mutualFundsSnapshot != nil,
                          !store.failed, !store.mutualFundsFailed, !store.isLoading, !store.mutualFundsLoading
                {
                    ContentUnavailableView("No Holdings", systemImage: "tray",
                                           description: Text("Kite returned no securities or mutual fund holdings."))
                }
            }
            .sheet(item: $inspected) { row in
                let analysis = store.analyzedRow(source: row.source, id: row.sourceRowID)
                switch row.record {
                case let .security(holding): HoldingInspection(store: store, holding: holding, analysis: analysis, allocationIsCurrent: store.performance != nil,
                                                               retrievedAt: row.retrievedAt, valuationDate: row.valuationDate)
                case let .mutualFund(holding): MutualFundInspection(store: store, holding: holding, analysis: analysis, allocationIsCurrent: store.performance != nil,
                                                                    retrievedAt: row.retrievedAt)
                }
            }
            .onReceive(store.$snapshot) { _ in discardSelection(source: .securities) }
            .onReceive(store.$mutualFundsSnapshot) { _ in discardSelection(source: .mutualFunds) }
            .onChange(of: query) { _, _ in selection = nil }
            .onChange(of: investmentType) { _, _ in selection = nil }
        }

        /// The mutual fund endpoint establishes fund type; securities carry only unknown type today.
        private enum InvestmentType: String, CaseIterable {
            case all = "All Types"
            case mutualFunds = "Mutual Funds"
            case unknown = "Unknown"
        }

        /// Display comparisons use the unrounded authoritative Decimal, keeping nil distinct from zero.
        private enum SortMeasure: String, CaseIterable {
            case currentValue = "Current Value"
            case investedCost = "Invested Cost"
            case returns = "Return"

            func value(_ row: HoldingsRow, in store: PortfolioStore) -> Decimal? {
                let values = row.values(in: store)
                switch self {
                case .currentValue: return values?.currentValue
                case .investedCost: return values?.investedCost
                case .returns: return values?.returnPercent
                }
            }
        }

        /// Unavailable values stay last in both directions instead of reversing with available numbers.
        private enum SortDirection: String, CaseIterable {
            case ascending = "Ascending"
            case descending = "Descending"
        }

        /// Stable name and source identity break ties without merging records or inventing financial values.
        private func precedes(_ left: HoldingsRow, _ right: HoldingsRow) -> Bool {
            let lhs = sortBy.value(left, in: store)
            let rhs = sortBy.value(right, in: store)
            switch (lhs, rhs) {
            case let (lhs?, rhs?) where lhs != rhs: return direction == .descending ? lhs > rhs : lhs < rhs
            case (nil, _?): return false
            case (_?, nil): return true
            default:
                let nameOrder = left.name.localizedStandardCompare(right.name)
                return nameOrder == .orderedSame ? left.id < right.id : nameOrder == .orderedAscending
            }
        }

        /// Native table selection, context menu and Return all inspect the same source record.
        private var table: some View {
            Table(visibleRows, selection: $selection) {
                TableColumn("Holding") { row in
                    VStack(alignment: .leading) {
                        Text(row.name)
                        if row.symbol != row.name {
                            Text(row.symbol).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.width(min: 130, ideal: 160)
                TableColumn("Type", value: \.typeName).width(80)
                TableColumn("Current Value") { row in Text(holdingMoney(row.values(in: store)?.currentValue)) }.width(min: 85, ideal: 100)
                TableColumn("Invested Cost") { row in Text(holdingMoney(row.values(in: store)?.investedCost)) }.width(min: 85, ideal: 100)
                TableColumn("Gain or Loss") { row in Text(holdingMoney(row.values(in: store)?.gain)) }.width(min: 85, ideal: 100)
                TableColumn("Return") { row in Text(holdingPercent(row.values(in: store)?.returnPercent)) }.width(75)
            }
            .frame(height: max(220, min(320, CGFloat(rows.count) * 44 + 40)))
            .accessibilityLabel("Holdings")
            .contextMenu(forSelectionType: String.self) { identifiers in
                Button("Inspect Holding") { inspect(identifiers.first) }
            } primaryAction: { identifiers in inspect(identifiers.first) }
        }

        /// Resolves a selection only against the currently visible source retrieval.
        private func inspect(_ id: String?) {
            inspected = visibleRows.first { $0.id == id }
        }

        /// Replacement and authority removal dismiss details instead of attaching them to a reused row ID.
        private func discardSelection(source: PortfolioHoldingPerformance.Source) {
            if selection?.hasPrefix(source.rawValue + ":") == true {
                selection = nil
            }
            if inspected?.source == source {
                inspected = nil
            }
        }
    }
#endif
