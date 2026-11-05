//
//  PortfolioAllocationView.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Native value-based concentration with visible text equivalents for every bar.
    struct PortfolioAllocationView: View {
        /// Only a current authoritative aggregate may provide allocation.
        let allocation: PortfolioAllocation

        var body: some View {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Allocation by Current Value").font(.title2).accessibilityAddTraits(.isHeader)
                    Text("Allocation coverage: \(allocation.valuedHoldings) of \(allocation.totalHoldings) holdings")
                    if allocation.valuedHoldings < allocation.totalHoldings {
                        Text("Incomplete allocation — percentages cover only valued holdings.")
                            .foregroundStyle(.secondary)
                    }
                    if allocation.totalHoldings == 0 {
                        Text("No ordinary holdings to allocate.")
                    } else if allocation.currentValue.map({ $0 > 0 }) != true {
                        Text("Allocation unavailable — no positive valued total.")
                    }
                    if allocation.excludedMTFHoldings > 0 {
                        Text("Holdings with excluded MTF components: \(allocation.excludedMTFHoldings)")
                    }
                    Text("Valued ordinary holdings: \(holdingMoney(allocation.currentValue))")
                        .accessibilityIdentifier("Allocation valued total")
                    if !allocation.largestHoldings.isEmpty {
                        Text("Largest Holdings").font(.headline).accessibilityAddTraits(.isHeader)
                        Text("Up to five holdings, ranked by current value.").font(.callout).foregroundStyle(.secondary)
                        ForEach(Array(allocation.largestHoldings.prefix(5).enumerated()), id: \.element.id) { index, holding in
                            allocationRow(title: "\(index + 1). \(holding.name)", value: holding.currentValue,
                                          percent: holding.allocationPercent, detail: holding.investmentType.allocationLabel,
                                          identifier: "Allocation holding \(index + 1)")
                        }
                    }
                    if !allocation.groups.isEmpty {
                        Divider()
                        Text("Investment Types").font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(allocation.groups) { group in
                            allocationRow(title: group.investmentType.allocationLabel, value: group.currentValue,
                                          percent: group.allocationPercent,
                                          detail: "Valued: \(group.valuedHoldings) of \(group.totalHoldings) holdings",
                                          identifier: "Allocation group \(group.id)")
                        }
                    }
                    Text("Security types and ETF underlying exposure are not supplied by these holdings sources.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Positions and trading funds remain separate from investment allocation.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }

        /// Labels and values convey the same information as bars without relying on color or position.
        private func allocationRow(title: String, value: Decimal?, percent: Decimal?, detail: String, identifier: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(holdingMoney(value)).monospacedDigit()
                    Text(holdingPercent(percent)).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if let percent {
                    ProgressView(value: NSDecimalNumber(decimal: percent).doubleValue, total: 100)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(holdingMoney(value)), \(holdingPercent(percent)), \(detail)")
            .accessibilityIdentifier(identifier)
        }
    }

    private extension HoldingInvestmentType {
        /// Group names state only the classification supported by the holdings source.
        var allocationLabel: String {
            switch self {
            case .unknown: "Unknown investment type"
            case .mutualFund: "Mutual funds"
            }
        }
    }
#endif
