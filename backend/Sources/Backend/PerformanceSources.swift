//
//  PerformanceSources.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import Shared

/// Latest source reads are scoped to KiteLogin authority and cleared before each source read.
struct PerformanceSources {
    /// Latest successfully read securities, absent while loading or after failure.
    var securities: SecuritiesHoldings?
    /// Latest successfully read mutual funds, absent while loading or after failure.
    var mutualFunds: MutualFundHoldings?

    /// Read identities prevent aggregation from silently substituting a newer or failed source.
    func aggregate(_ request: PortfolioPerformanceRequest) throws -> PortfolioPerformance {
        guard let securities, let mutualFunds,
              securities.readID == request.securitiesReadID, mutualFunds.readID == request.mutualFundsReadID
        else { throw KiteLogin.RecoveryFailure(code: .portfolioUnavailable) }
        let securitiesISINs = Set(securities.holdings.map(\.isin).filter { !$0.isEmpty })
        let fundISINs = Set(mutualFunds.holdings.map(\.symbol).filter { !$0.isEmpty })
        let overlaps = securitiesISINs.intersection(fundISINs)
        let projection = securities.holdings.map {
            project(source: .securities, id: $0.id, values: $0.performance, overlap: overlaps.contains($0.isin))
        } + mutualFunds.holdings.map {
            project(source: .mutualFunds, id: $0.id, values: $0.performance, overlap: overlaps.contains($0.symbol))
        }
        let all = projection.map(\.values)
        let rows = all.filter { !$0.excludedMTFOnly }
        let costs = rows.compactMap(\.investedCost)
        let values = rows.compactMap(\.currentValue)
        let matched = rows.filter { $0.gain != nil }
        let gain = sum(matched.compactMap(\.gain), total: rows.count)
        let matchedCost = sum(matched.compactMap(\.investedCost), total: rows.count)
        let matchedValue = sum(matched.compactMap(\.currentValue), total: rows.count)
        let percent = matchedCost.flatMap { cost in cost > 0 ? gain.flatMap { HoldingValuation.finite($0 / cost * 100) } : nil }
        return PortfolioPerformance(sources: request, investedCost: sum(costs, total: rows.count), currentValue: sum(values, total: rows.count),
                                    gain: gain, returnPercent: percent, matchedCost: matchedCost, matchedValue: matchedValue,
                                    totalHoldings: rows.count, costCount: costs.count, valueCount: values.count,
                                    returnCount: matched.count, excludedMTFCount: all.count - rows.count, rows: projection)
    }

    /// Cross-source ambiguity withholds calculations while retaining a source-qualified inspection row.
    private func project(source: PortfolioHoldingPerformance.Source, id: String, values: HoldingPerformance?, overlap: Bool) -> PortfolioHoldingPerformance {
        let unavailable = HoldingPerformance(quantity: nil, investedCost: nil, currentValue: nil, gain: nil, returnPercent: nil)
        return PortfolioHoldingPerformance(source: source, sourceRowID: id, values: overlap ? unavailable : values ?? unavailable, overlapsSources: overlap)
    }

    /// Empty successful inventory is zero; no available contribution from nonempty inventory is unavailable.
    private func sum(_ values: [Decimal], total: Int) -> Decimal? {
        guard !values.isEmpty || total == 0 else { return nil }
        return HoldingValuation.finite(values.reduce(0, +))
    }
}
