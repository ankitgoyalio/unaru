//
//  TradingFundsSource.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import KiteConnect
import Shared

/// Restricts SDK margin data to credential-free, broker-reported balances.
enum TradingFundsSource {
    /// Does not add cash, collateral, pay-in, or already aggregated utilisation components.
    static func normalize(_ funds: KiteAccountMargins) -> [TradingFundsSegment] {
        [("equity", funds.equity), ("commodity", funds.commodity)].map { segment, row in
            TradingFundsSegment(segment: segment, enabled: row.enabled, available: row.net,
                                utilised: row.utilised.debits,
                                availableComponents: [
                                    "cash": row.available.cash, "openingBalance": row.available.openingBalance,
                                    "liveBalance": row.available.liveBalance, "intradayPayin": row.available.intradayPayin,
                                    "adhocMargin": row.available.adhocMargin, "collateral": row.available.collateral,
                                ], utilisedComponents: [
                                    "m2mUnrealised": row.utilised.m2mUnrealised, "m2mRealised": row.utilised.m2mRealised,
                                    "debits": row.utilised.debits, "span": row.utilised.span,
                                    "optionPremium": row.utilised.optionPremium, "holdingSales": row.utilised.holdingSales,
                                    "exposure": row.utilised.exposure, "liquidCollateral": row.utilised.liquidCollateral,
                                    "delivery": row.utilised.delivery, "stockCollateral": row.utilised.stockCollateral,
                                    "turnover": row.utilised.turnover, "payout": row.utilised.payout,
                                ])
        }
    }
}
