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
        let isinCounts = rows.reduce(into: [String: Int]()) { $0[$1.isin, default: 0] += 1 }
        let identityCounts = rows.reduce(into: [[String]: Int]()) { $0[[$1.exchange.rawValue, $1.tradingSymbol, $1.product.rawValue], default: 0] += 1 }
        return rows.enumerated().map { index, row in
            var limitations: [SecurityHolding.Limitation] = [.nameUnavailable, .classificationUnavailable, .valuationDateUnavailable]
            if row.averagePrice <= 0 {
                limitations.append(.acquisitionPriceUnavailable)
            }
            if row.lastPrice <= 0 {
                limitations.append(.marketPriceUnavailable)
            }
            if row.quantity < 0 || row.t1Quantity < 0 || (row.shortQuantity ?? 0) != 0 || (row.usedQuantity ?? 0) < 0 || row.product.rawValue != "CNC" {
                limitations.append(.quantityUnusable)
            }
            if row.collateralQuantity != 0 {
                limitations.append(.collateralRelationshipUnknown)
            }
            if let mtf = row.mtf, mtf.quantity < 0 || mtf.usedQuantity != 0 {
                limitations.append(.mtfRelationshipUnknown)
            }
            if row.discrepancy {
                limitations.append(.discrepancy)
            }
            if (!row.isin.isEmpty && isinCounts[row.isin, default: 0] > 1) ||
                identityCounts[[row.exchange.rawValue, row.tradingSymbol, row.product.rawValue], default: 0] > 1
            {
                limitations.append(.overlappingRecords)
            }
            let quantityUsable = !limitations.contains(where: { [.quantityUnusable, .collateralRelationshipUnknown, .mtfRelationshipUnknown, .overlappingRecords, .discrepancy].contains($0) })
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
                performance: HoldingValuation.calculate(
                    quantity: Decimal(row.quantity) + Decimal(row.t1Quantity), averagePrice: row.averagePrice, price: row.lastPrice,
                    quantityUsable: quantityUsable,
                    excludedMTFOnly: row.quantity == 0 && row.t1Quantity == 0 && (row.mtf?.quantity ?? 0) > 0 && quantityUsable,
                ),
            )
        }
    }
}
