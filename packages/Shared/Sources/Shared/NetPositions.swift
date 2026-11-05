//
//  NetPositions.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

public import Foundation

/// A successful net-positions read, with no addition of the overlapping day collection.
public struct NetPositions: Codable, Sendable {
    /// Every net row remains inspectable, including returned closed positions.
    public let positions: [TradingPosition]
    /// Response retrieval time, never a confirmed market-price timestamp.
    public let retrievedAt: Date
    /// Market-price date, absent when the broker supplies none.
    public let valuationDate: String?

    /// Creates a credential-free source result. Failures use the HTTP problem contract.
    public init(positions: [TradingPosition], retrievedAt: Date, valuationDate: String? = nil) {
        self.positions = positions
        self.retrievedAt = retrievedAt
        self.valuationDate = valuationDate
    }
}

/// Read-only trading exposure and activity, distinct from current investment holdings.
public struct TradingPosition: Codable, Sendable, Identifiable {
    /// Source row identity within this retrieval, independent of symbol or product.
    public let id: String
    /// Broker trading symbol.
    public let symbol: String
    /// Exchange code, including unfamiliar provider values.
    public let exchange: String
    /// Broker instrument token, which can be reused after expiry.
    public let instrumentToken: UInt32
    /// Broker margin product code.
    public let product: String
    /// Current exposure or a returned closed position, determined from signed net quantity.
    public let state: State
    /// Signed net quantity. Negative quantities represent short exposure.
    public let quantity: Int64
    /// Signed quantity carried from the previous trading day.
    public let overnightQuantity: Int64
    /// Contract multiplier, retained without conversion to ordinary security units.
    public let multiplier: Int64
    /// Broker average execution price, including an unusable zero.
    public let averagePrice: Decimal
    /// Broker last price. A nonpositive value does not establish an available market price.
    public let lastPrice: Decimal
    /// Broker previous close, retained even when unavailable as a usable price.
    public let closePrice: Decimal
    /// Broker position value, never added to investment value.
    public let value: Decimal
    /// Broker total trading P&L, without local recomputation.
    public let pnl: Decimal
    /// Broker realised trading P&L, separate from holdings returns.
    public let realised: Decimal
    /// Broker unrealised trading P&L, separate from holdings returns.
    public let unrealised: Decimal
    /// Broker mark-to-market trading P&L.
    public let m2m: Decimal
    /// Cumulative bought quantity, reported by Kite.
    public let buyQuantity: Int64
    /// Cumulative bought average price, reported by Kite.
    public let buyPrice: Decimal
    /// Cumulative bought value, reported by Kite.
    public let buyValue: Decimal
    /// Cumulative bought mark-to-market value, reported by Kite.
    public let buyM2M: Decimal
    /// Cumulative sold quantity, reported by Kite.
    public let sellQuantity: Int64
    /// Cumulative sold average price, reported by Kite.
    public let sellPrice: Decimal
    /// Cumulative sold value, reported by Kite.
    public let sellValue: Decimal
    /// Cumulative sold mark-to-market value, reported by Kite.
    public let sellM2M: Decimal
    /// Current-day bought quantity, reported by Kite.
    public let dayBuyQuantity: Int64
    /// Current-day bought average price, reported by Kite.
    public let dayBuyPrice: Decimal
    /// Current-day bought value, reported by Kite.
    public let dayBuyValue: Decimal
    /// Current-day sold quantity, reported by Kite.
    public let daySellQuantity: Int64
    /// Current-day sold average price, reported by Kite.
    public let daySellPrice: Decimal
    /// Current-day sold value, reported by Kite.
    public let daySellValue: Decimal

    /// Groups net rows without reconstructing trades or holdings.
    public enum State: String, Codable, Sendable {
        /// A nonzero signed net quantity.
        case current
        /// A zero net quantity returned by Kite.
        case closed
    }

    /// Preserves supported broker fields without exposing arbitrary provider metadata.
    public init(
        id: String, symbol: String, exchange: String,
        instrumentToken: UInt32, product: String, state: State,
        quantity: Int64, overnightQuantity: Int64, multiplier: Int64,
        averagePrice: Decimal, lastPrice: Decimal, closePrice: Decimal,
        value: Decimal, pnl: Decimal, realised: Decimal,
        unrealised: Decimal, m2m: Decimal, buyQuantity: Int64,
        buyPrice: Decimal, buyValue: Decimal, buyM2M: Decimal,
        sellQuantity: Int64, sellPrice: Decimal, sellValue: Decimal,
        sellM2M: Decimal, dayBuyQuantity: Int64, dayBuyPrice: Decimal,
        dayBuyValue: Decimal, daySellQuantity: Int64, daySellPrice: Decimal,
        daySellValue: Decimal,
    ) {
        self.id = id
        self.symbol = symbol
        self.exchange = exchange
        self.instrumentToken = instrumentToken
        self.product = product
        self.state = state
        self.quantity = quantity
        self.overnightQuantity = overnightQuantity
        self.multiplier = multiplier
        self.averagePrice = averagePrice
        self.lastPrice = lastPrice
        self.closePrice = closePrice
        self.value = value
        self.pnl = pnl
        self.realised = realised
        self.unrealised = unrealised
        self.m2m = m2m
        self.buyQuantity = buyQuantity
        self.buyPrice = buyPrice
        self.buyValue = buyValue
        self.buyM2M = buyM2M
        self.sellQuantity = sellQuantity
        self.sellPrice = sellPrice
        self.sellValue = sellValue
        self.sellM2M = sellM2M
        self.dayBuyQuantity = dayBuyQuantity
        self.dayBuyPrice = dayBuyPrice
        self.dayBuyValue = dayBuyValue
        self.daySellQuantity = daySellQuantity
        self.daySellPrice = daySellPrice
        self.daySellValue = daySellValue
    }
}
