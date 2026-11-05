//
//  NetPositionSource.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import KiteConnect
import Shared

/// Maps only the net collection into credential-free broker inspection fields.
enum NetPositionSource {
    /// Preserves source rows, signed exposure, multipliers and broker P&L without aggregation.
    static func normalize(_ rows: [KitePosition]) -> [TradingPosition] {
        rows.enumerated().map { index, row in
            TradingPosition(
                id: String(index), symbol: row.tradingSymbol, exchange: row.exchange.rawValue,
                instrumentToken: row.instrumentToken, product: row.product.rawValue, state: row.quantity == 0 ? .closed : .current,
                quantity: row.quantity, overnightQuantity: row.overnightQuantity, multiplier: row.multiplier,
                averagePrice: row.averagePrice, lastPrice: row.lastPrice, closePrice: row.closePrice,
                value: row.value, pnl: row.pnl, realised: row.realised,
                unrealised: row.unrealised, m2m: row.m2m, buyQuantity: row.buyQuantity,
                buyPrice: row.buyPrice, buyValue: row.buyValue, buyM2M: row.buyM2M,
                sellQuantity: row.sellQuantity, sellPrice: row.sellPrice, sellValue: row.sellValue,
                sellM2M: row.sellM2M, dayBuyQuantity: row.dayBuyQuantity, dayBuyPrice: row.dayBuyPrice,
                dayBuyValue: row.dayBuyValue, daySellQuantity: row.daySellQuantity, daySellPrice: row.daySellPrice,
                daySellValue: row.daySellValue,
            )
        }
    }
}
