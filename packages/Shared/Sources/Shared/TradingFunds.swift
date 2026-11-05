//
//  TradingFunds.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

public import Foundation

/// One successful trading-funds retrieval, separate from holdings and investment performance.
public struct TradingFunds: Codable, Sendable {
    /// Documented account segments, including disabled segments.
    public let segments: [TradingFundsSegment]
    /// When the helper obtained these balances, not a market valuation date.
    public let retrievedAt: Date

    /// Creates an in-memory, credential-free source response.
    public init(segments: [TradingFundsSegment], retrievedAt: Date) {
        self.segments = segments
        self.retrievedAt = retrievedAt
    }
}

/// Broker-reported balances; components overlap and must never be summed into wealth.
public struct TradingFundsSegment: Codable, Sendable, Identifiable {
    /// Provider segment identifier, also the stable inspection identity.
    public let segment: String
    /// Whether Kite enables this segment; disabled balances do not imply trading availability.
    public let enabled: Bool
    /// Kite's net balance available for trading, preserved without recomputation.
    public let available: Decimal
    /// Kite's total utilised margin (`debits`), including legitimate negative or zero values.
    public let utilised: Decimal
    /// Whitelisted available-funds components using SDK property names, not additional balances.
    public let availableComponents: [String: Decimal]
    /// Whitelisted utilisation components using SDK property names, not additive investment costs.
    public let utilisedComponents: [String: Decimal]
    /// One row per documented provider segment.
    public var id: String {
        segment
    }

    /// Creates a broker-reported segment with inspectable component values.
    public init(segment: String, enabled: Bool, available: Decimal, utilised: Decimal,
                availableComponents: [String: Decimal], utilisedComponents: [String: Decimal])
    {
        self.segment = segment
        self.enabled = enabled
        self.available = available
        self.utilised = utilised
        self.availableComponents = availableComponents
        self.utilisedComponents = utilisedComponents
    }
}
