//
//  HoldingValuation.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import Shared

/// Authoritative Decimal arithmetic for current ordinary inventory; provider P&L is never an input.
enum HoldingValuation {
    /// Independent cost/value eligibility preserves usable value when acquisition cost is unavailable.
    static func calculate(quantity: Decimal, averagePrice: Decimal, price: Decimal, quantityUsable: Bool, excludedMTFOnly: Bool = false) -> HoldingPerformance {
        let held = quantityUsable && quantity > 0 ? quantity : nil
        let cost = held.flatMap { averagePrice > 0 ? finite($0 * averagePrice) : nil }
        let value = held.flatMap { price > 0 ? finite($0 * price) : nil }
        let gain = cost.flatMap { cost in value.flatMap { finite($0 - cost) } }
        let percent = cost.flatMap { cost in cost > 0 ? gain.flatMap { finite($0 / cost * 100) } : nil }
        return HoldingPerformance(quantity: held, investedCost: cost, currentValue: value, gain: gain,
                                  returnPercent: percent, excludedMTFOnly: excludedMTFOnly)
    }

    /// Decimal overflow must not publish an invalid financial value.
    static func finite(_ value: Decimal) -> Decimal? {
        value.isNaN ? nil : value
    }
}
