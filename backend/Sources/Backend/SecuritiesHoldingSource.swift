//
//  SecuritiesHoldingSource.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import KiteConnect
import Shared

/// Restricts real SDK responses to supported, credential-free inspection data.
enum SecuritiesHoldingSource {
    /// Every broker row stays inspectable, including unusable and potentially overlapping inventory.
    static func normalize(_ rows: [KiteHolding]) -> [SecurityHolding] {
        rows.enumerated().map { index, row in
            var limitations: [SecurityHolding.Limitation] = [.nameUnavailable, .classificationUnavailable, .valuationDateUnavailable]
            if row.averagePrice <= 0 {
                limitations.append(.acquisitionPriceUnavailable)
            }
            if row.lastPrice <= 0 {
                limitations.append(.marketPriceUnavailable)
            }
            if row.quantity < 0 || row.t1Quantity < 0 {
                limitations.append(.quantityUnusable)
            }
            if row.collateralQuantity != 0 {
                limitations.append(.collateralRelationshipUnknown)
            }
            if let mtf = row.mtf, mtf.quantity != 0 || mtf.usedQuantity != 0 {
                limitations.append(.mtfRelationshipUnknown)
            }
            if row.discrepancy {
                limitations.append(.discrepancy)
            }
            if rows.enumerated().contains(where: { otherIndex, other in
                otherIndex != index && (
                    (!row.isin.isEmpty && row.isin == other.isin) ||
                        (row.exchange == other.exchange && row.tradingSymbol == other.tradingSymbol && row.product == other.product)
                )
            }) {
                limitations.append(.overlappingRecords)
            }
            return SecurityHolding(
                id: String(index), symbol: row.tradingSymbol, exchange: row.exchange.rawValue,
                instrumentToken: row.instrumentToken, isin: row.isin, product: row.product.rawValue,
                quantity: row.quantity, t1Quantity: row.t1Quantity, realisedQuantity: row.realisedQuantity,
                authorisedQuantity: row.authorisedQuantity, openingQuantity: row.openingQuantity,
                usedQuantity: row.usedQuantity, shortQuantity: row.shortQuantity,
                collateralQuantity: row.collateralQuantity, collateralType: row.collateralType,
                authorisedDate: row.authorisedDate, discrepancy: row.discrepancy,
                averagePrice: row.averagePrice, lastPrice: row.lastPrice,
                mtf: row.mtf.map { HoldingMTF(quantity: $0.quantity, usedQuantity: $0.usedQuantity,
                                              averagePrice: $0.averagePrice, value: $0.value, initialMargin: $0.initialMargin) },
                limitations: limitations,
            )
        }
    }
}
