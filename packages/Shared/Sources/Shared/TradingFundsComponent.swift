//
//  TradingFundsComponent.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

/// Whitelisted SDK component names, shared by normalization and inspection without summing overlapping balances.
public enum TradingFundsComponent: String, Codable, CodingKey, CodingKeyRepresentable, Sendable {
    /// Available cash, already including intraday pay-in.
    case cash
    /// Balance at the start of the trading day.
    case openingBalance
    /// Broker-reported live balance.
    case liveBalance
    /// Pay-in received during the day.
    case intradayPayin
    /// Additional margin provided by the broker.
    case adhocMargin
    /// Available margin from pledged collateral.
    case collateral
    /// Unrealised intraday mark-to-market utilisation.
    case m2mUnrealised
    /// Realised intraday mark-to-market utilisation.
    case m2mRealised
    /// Total utilised margin, already containing other components.
    case debits
    /// SPAN margin utilisation.
    case span
    /// Option premium utilisation.
    case optionPremium
    /// Utilisation attributed to holding sales.
    case holdingSales
    /// Exposure margin utilisation.
    case exposure
    /// Liquid collateral utilisation.
    case liquidCollateral
    /// Delivery margin utilisation.
    case delivery
    /// Stock collateral utilisation.
    case stockCollateral
    /// Turnover utilisation.
    case turnover
    /// Broker-reported payout.
    case payout

    /// Preserves the existing JSON object keys for component dictionaries.
    public var codingKey: any CodingKey {
        self
    }

    /// Decodes a documented SDK component name from a JSON object key.
    public init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}
