//
//  PortfolioPerformanceView.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// A compact native summary consumes backend values without recomputing financial measures.
    struct PortfolioPerformanceView: View {
        @EnvironmentObject private var connection: BackendConnection
        /// Shared source and aggregate lifetime across windows.
        @ObservedObject var store: PortfolioStore

        var body: some View {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current-Holdings Unrealised Performance").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Connected Kite account · Ordinary holdings only · MTF excluded")
                        .foregroundStyle(.secondary)
                    if let result = store.performance {
                        HStack(alignment: .top, spacing: 24) {
                            metric("Invested Cost", holdingMoney(result.investedCost), id: "Performance invested cost")
                            metric("Current Value", holdingMoney(result.currentValue), id: "Performance current value")
                            metric("Gain or Loss", holdingMoney(result.gain), id: "Performance gain")
                            metric("Unrealised Return", holdingPercent(result.returnPercent), id: "Performance return")
                        }
                        Text("Value coverage: \(result.valueCount) of \(result.totalHoldings) holdings")
                        Text("Cost coverage: \(result.costCount) of \(result.totalHoldings) holdings")
                        Text("Return coverage: \(result.returnCount) of \(result.totalHoldings) holdings")
                        Text("Matched return cost: \(holdingMoney(result.matchedCost))")
                            .accessibilityIdentifier("Performance matched cost")
                        Text("Matched return value: \(holdingMoney(result.matchedValue))")
                        if result.excludedMTFCount > 0 {
                            Text("\(result.excludedMTFCount) MTF-only holdings excluded from ordinary coverage")
                        }
                        if result.valueCount < result.totalHoldings || result.returnCount < result.totalHoldings {
                            Text("Incomplete coverage — unavailable contributions are excluded. Value and return may cover different holdings.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Combined totals unavailable until both holdings sources refresh successfully.")
                        if store.performanceFailed {
                            Text("Couldn’t load combined performance")
                            Button("Retry Performance") { connection.refreshPortfolio() }
                        }
                    }
                    Text("Unrealised performance of current holdings. Excludes realised gains, dividends and annualised returns. Source price dates may differ.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }

        /// Each measure has a stable accessible identity and retains its user-visible value.
        private func metric(_ title: String, _ value: String, id: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.title2).monospacedDigit().accessibilityIdentifier(id)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Inspection uses the same backend row values as the holdings table and aggregate inputs.
    struct HoldingPerformanceView: View {
        /// Nil identifies an older inspection-only contract with no calculated values.
        let performance: HoldingPerformance?
        /// Cross-source identity overlap explains why otherwise usable prices cannot contribute.
        let overlapsSources: Bool

        var body: some View {
            GroupBox("Current-Holdings Unrealised Performance") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Usable ordinary quantity", value: performance?.quantity.map(mutualFundDecimal) ?? "Unavailable")
                    LabeledContent("Invested cost") { Text(holdingMoney(performance?.investedCost)).accessibilityIdentifier("Holding invested cost") }
                    LabeledContent("Current value") { Text(holdingMoney(performance?.currentValue)).accessibilityIdentifier("Holding current value") }
                    LabeledContent("Gain or loss") { Text(holdingMoney(performance?.gain)).accessibilityIdentifier("Holding gain") }
                    LabeledContent("Unrealised return", value: holdingPercent(performance?.returnPercent))
                    if overlapsSources {
                        Text("Potential overlap across holdings sources — calculated contribution unavailable.")
                    }
                    if performance?.excludedMTFOnly == true {
                        Text("MTF-only holding — excluded from ordinary investment calculations.")
                    } else if performance?.currentValue == nil || performance?.gain == nil {
                        Text("Incomplete calculation coverage. See source fields and data limitations.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
    }

    /// Display rounding preserves the backend's Decimal value, including legitimate zero.
    func holdingMoney(_ value: Decimal?) -> String {
        value.map { $0.formatted(.currency(code: "INR")) } ?? "Unavailable"
    }

    /// Backend percentages are already multiplied by 100; formatting performs no return calculation.
    func holdingPercent(_ value: Decimal?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(2))) + "%" } ?? "Unavailable"
    }
#endif
