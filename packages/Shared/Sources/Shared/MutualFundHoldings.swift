//
//  MutualFundHoldings.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

public import Foundation

/// A successful mutual fund source read, including a successful empty response.
public struct MutualFundHoldings: Codable, Sendable {
    /// Every provider row in source order; possible overlaps remain separate.
    public let holdings: [MutualFundHolding]
    /// When the helper obtained this source, distinct from each holding's NAV date.
    public let retrievedAt: Date

    /// Creates a credential-free, memory-only mutual fund snapshot.
    public init(holdings: [MutualFundHolding], retrievedAt: Date) {
        self.holdings = holdings
        self.retrievedAt = retrievedAt
    }
}

/// Broker-reported mutual fund units, without an inferred return or inventory adjustment.
public struct MutualFundHolding: Codable, Sendable, Identifiable {
    /// Row identity within this retrieval; folios and symbols need not be unique.
    public let id: String
    /// Scheme name reported by Kite.
    public let fund: String
    /// Fund trading symbol (ISIN), preserved even when another row shares it.
    public let symbol: String
    /// Optional AMC folio, retained without using it as a row key.
    public let folio: String?
    /// Fractional units, without whole-unit rounding or pledge adjustments.
    public let quantity: Decimal
    /// Raw acquisition price; nonpositive values do not establish usable cost.
    public let averagePrice: Decimal
    /// Latest available NAV; nonpositive values do not establish usable valuation.
    public let lastPrice: Decimal
    /// Broker-confirmed calendar date of the NAV, absent when unavailable.
    public let navDate: String?
    /// Pledged units, with no assumed relationship to the primary quantity.
    public let pledgedQuantity: Decimal?

    /// Reasons this row cannot imply complete cost, valuation, or inventory coverage.
    public let limitations: [Limitation]

    /// Explanations use supported source evidence without inventing financial contributions.
    public enum Limitation: String, Codable, Sendable {
        /// A missing calendar date must not be replaced with retrieval time.
        case navDateUnavailable
        /// A nonpositive acquisition price does not establish zero acquisition cost.
        case acquisitionPriceUnavailable
        /// A nonpositive NAV cannot establish current value.
        case navUnavailable
        /// Nonpositive units do not establish usable current inventory.
        case quantityUnusable
        /// Pledge units have no verified additive or deductive relationship.
        case pledgeRelationshipUnknown
        /// Possible duplicate inventory stays inspectable without a guessed contribution.
        case overlappingRecords
    }

    /// Preserves the supported source fields without arbitrary provider metadata or credentials.
    public init(id: String, fund: String, symbol: String, folio: String?, quantity: Decimal,
                averagePrice: Decimal, lastPrice: Decimal, navDate: String?, pledgedQuantity: Decimal?, limitations: [Limitation])
    {
        self.id = id
        self.fund = fund
        self.symbol = symbol
        self.folio = folio
        self.quantity = quantity
        self.averagePrice = averagePrice
        self.lastPrice = lastPrice
        self.navDate = navDate
        self.pledgedQuantity = pledgedQuantity
        self.limitations = limitations
    }
}
