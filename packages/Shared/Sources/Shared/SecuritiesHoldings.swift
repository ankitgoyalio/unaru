//
//  SecuritiesHoldings.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

public import Foundation

/// One successful source read. An empty array is a loaded empty source, never a read failure.
public struct SecuritiesHoldings: Codable, Sendable {
    /// Rows retain their source order and identity, including potentially overlapping records.
    public let holdings: [SecurityHolding]
    /// Opaque identity for aggregating exactly this successful source read.
    public let readID: String?
    /// When the helper obtained the source, not the time of the market price.
    public let retrievedAt: Date
    /// A source price date, absent when Kite supplies none.
    public let valuationDate: String?

    /// Creates a credential-free source result; failures use the HTTP problem contract.
    public init(holdings: [SecurityHolding], retrievedAt: Date, valuationDate: String? = nil, readID: String? = UUID().uuidString) {
        self.holdings = holdings
        self.readID = readID
        self.retrievedAt = retrievedAt
        self.valuationDate = valuationDate
    }
}

/// A broker-reported security, distinct from trading positions and mutual fund holdings.
public struct SecurityHolding: Codable, Sendable, Identifiable {
    /// Source row identity within this retrieval; never a symbol-only instrument key.
    public let id: String
    /// Trading symbol supplied by Kite.
    public let symbol: String
    /// Full name, unavailable when not supplied by this source.
    public let name: String?
    /// Exchange code, including unfamiliar provider values.
    public let exchange: String
    /// Broker instrument identifier, retained for inspection rather than used alone as identity.
    public let instrumentToken: UInt32
    /// Depository identifier; absence or duplicates do not justify merging rows.
    public let isin: String
    /// Broker product code, distinct from an investment classification.
    public let product: String
    /// Classification requires supported metadata; exchange trading alone establishes no asset type.
    public let investmentType: InvestmentType
    /// Settled quantity reported by Kite, without subtracting used or MTF quantities.
    public let quantity: Int64
    /// Unsettled quantity, retained separately.
    public let t1Quantity: Int64
    /// Separate broker-reported realised quantity.
    public let realisedQuantity: Int64
    /// Broker-authorised delivery quantity.
    public let authorisedQuantity: Int64
    /// Beginning-of-day inventory; not an additional holding.
    public let openingQuantity: Int64
    /// Sold quantity, not a further deduction from quantity.
    public let usedQuantity: Int64?
    /// Short-delivery quantity, if provided.
    public let shortQuantity: Int64?
    /// Pledged quantity, with no assumed additive or deductive relationship.
    public let collateralQuantity: Int64
    /// Raw collateral category, when supplied.
    public let collateralType: String?
    /// Authorisation time, never a market-price valuation date.
    public let authorisedDate: Date?
    /// Whether Kite flags a holding discrepancy.
    public let discrepancy: Bool
    /// Raw acquisition price; nonpositive values do not establish usable cost.
    public let averagePrice: Decimal
    /// Raw last price; nonpositive values do not establish a usable market price.
    public let lastPrice: Decimal
    /// Broker financing data, separate from ordinary holding quantities and prices.
    public let mtf: HoldingMTF?
    /// Authoritative ordinary holding calculations, absent in older inspection-only responses.
    public let performance: HoldingPerformance?
    /// Reasons a row must not imply complete classification or valuation coverage.
    public let limitations: [Limitation]

    /// Only classifications supported by source metadata belong here.
    public enum InvestmentType: String, Codable, Sendable {
        /// The holdings operation does not supply security-type metadata.
        case unknown
    }

    /// Credential-free coverage explanations, without raw upstream diagnostics.
    public enum Limitation: String, Codable, Sendable {
        /// This source has no security name.
        case nameUnavailable
        /// An exchange-traded security is not necessarily direct equity exposure.
        case classificationUnavailable
        /// Retrieval time must not be substituted for a price timestamp.
        case valuationDateUnavailable
        /// A nonpositive acquisition price does not establish a zero investment cost.
        case acquisitionPriceUnavailable
        /// A nonpositive last price cannot establish current value.
        case marketPriceUnavailable
        /// A negative inventory field is not usable ordinary inventory.
        case quantityUnusable
        /// Pledge fields have no verified additive or deductive relationship.
        case collateralRelationshipUnknown
        /// Financing sale relationships require further provider reconciliation.
        case mtfRelationshipUnknown
        /// Potentially overlapping records remain visible without an invented relationship.
        case overlappingRecords
        /// The provider reports an inventory discrepancy.
        case discrepancy
    }

    /// Preserves the supported source fields without arbitrary provider metadata or credentials.
    public init(
        id: String, symbol: String, name: String? = nil, exchange: String, instrumentToken: UInt32,
        isin: String, product: String, investmentType: InvestmentType = .unknown,
        quantity: Int64, t1Quantity: Int64, realisedQuantity: Int64, authorisedQuantity: Int64,
        openingQuantity: Int64, usedQuantity: Int64?, shortQuantity: Int64?, collateralQuantity: Int64,
        collateralType: String?, authorisedDate: Date?, discrepancy: Bool,
        averagePrice: Decimal, lastPrice: Decimal, mtf: HoldingMTF?, limitations: [Limitation],
        performance: HoldingPerformance? = nil,
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.instrumentToken = instrumentToken
        self.isin = isin
        self.product = product
        self.investmentType = investmentType
        self.quantity = quantity
        self.t1Quantity = t1Quantity
        self.realisedQuantity = realisedQuantity
        self.authorisedQuantity = authorisedQuantity
        self.openingQuantity = openingQuantity
        self.usedQuantity = usedQuantity
        self.shortQuantity = shortQuantity
        self.collateralQuantity = collateralQuantity
        self.collateralType = collateralType
        self.authorisedDate = authorisedDate
        self.discrepancy = discrepancy
        self.averagePrice = averagePrice
        self.lastPrice = lastPrice
        self.mtf = mtf
        self.performance = performance
        self.limitations = limitations
    }
}

/// Gross broker-reported MTF details, not financing-adjusted investment performance.
public struct HoldingMTF: Codable, Sendable {
    /// Financed quantity, separate from ordinary inventory.
    public let quantity: Int64
    /// Financed quantity sold, preserved without guessed netting.
    public let usedQuantity: Int64
    /// Average acquisition price for the financed component.
    public let averagePrice: Decimal
    /// Gross broker-reported security value.
    public let value: Decimal
    /// Initial margin, not an investment cost or net equity value.
    public let initialMargin: Decimal

    /// Creates the separate financing inspection contract.
    public init(quantity: Int64, usedQuantity: Int64, averagePrice: Decimal, value: Decimal, initialMargin: Decimal) {
        self.quantity = quantity
        self.usedQuantity = usedQuantity
        self.averagePrice = averagePrice
        self.value = value
        self.initialMargin = initialMargin
    }
}
