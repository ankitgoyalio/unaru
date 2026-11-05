//
//  HoldingAllocation.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import Shared

/// Allocation consumes final valuation eligibility, never broker inventory or cost arithmetic again.
enum HoldingAllocation {
    /// Produces mutually exclusive source-supported groups and a stable current-value ranking.
    static func analyze(_ rows: [PortfolioHoldingPerformance], securities: SecuritiesHoldings, mutualFunds: MutualFundHoldings, currentValue: Decimal?) -> PortfolioAllocation {
        let ordinary = rows.filter { !$0.values.excludedMTFOnly }
        let names = Dictionary(uniqueKeysWithValues: securities.holdings.map { ("securities:" + $0.id, $0.name ?? $0.symbol) }
            + mutualFunds.holdings.map { ("mutualFunds:" + $0.id, $0.fund) })
        let ranked = ordinary.compactMap { row -> PortfolioAllocationHolding? in
            guard let value = row.values.currentValue else { return nil }
            return PortfolioAllocationHolding(source: row.source, sourceRowID: row.sourceRowID, name: names[row.id] ?? row.sourceRowID,
                                              investmentType: type(row), currentValue: value, allocationPercent: percent(value, total: currentValue))
        }.sorted { $0.currentValue == $1.currentValue ? $0.id < $1.id : $0.currentValue > $1.currentValue }
        let grouped = Dictionary(grouping: ordinary, by: type)
        let groups = [HoldingInvestmentType.unknown, .mutualFund].compactMap { type -> PortfolioAllocationGroup? in
            guard let members = grouped[type] else { return nil }
            let values = members.compactMap(\.values.currentValue)
            let value = values.isEmpty ? nil : HoldingValuation.finite(values.reduce(0, +))
            return PortfolioAllocationGroup(investmentType: type, currentValue: value, allocationPercent: value.flatMap { percent($0, total: currentValue) },
                                            totalHoldings: members.count, valuedHoldings: values.count)
        }
        let financed = securities.holdings.filter { ($0.mtf?.quantity ?? 0) != 0 || ($0.mtf?.usedQuantity ?? 0) != 0 }.count
        return PortfolioAllocation(currentValue: currentValue, totalHoldings: ordinary.count, valuedHoldings: ranked.count,
                                   excludedMTFHoldings: financed, largestHoldings: ranked, groups: groups)
    }

    /// The securities endpoint has no supported security type; fund source membership establishes only mutual fund.
    private static func type(_ row: PortfolioHoldingPerformance) -> HoldingInvestmentType {
        row.source == .mutualFunds ? .mutualFund : .unknown
    }

    /// Empty, missing, overflowed and nonpositive denominators never fabricate a weight.
    private static func percent(_ value: Decimal, total: Decimal?) -> Decimal? {
        total.flatMap { $0 > 0 ? HoldingValuation.finite(value / $0 * 100) : nil }
    }
}
