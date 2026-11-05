//
//  MutualFundHoldingSource.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import KiteConnect
import Shared

/// Maps the pinned SDK's mutual fund source to credential-free inspection fields.
enum MutualFundHoldingSource {
    /// Retains fractional units and individual calendar dates without merging broker rows.
    static func normalize(_ rows: [KiteMutualFundHolding]) -> [MutualFundHolding] {
        rows.enumerated().map { index, row in
            var limitations: [MutualFundHolding.Limitation] = []
            if row.lastPriceDate == nil {
                limitations.append(.navDateUnavailable)
            }
            if row.averagePrice <= 0 {
                limitations.append(.acquisitionPriceUnavailable)
            }
            if row.lastPrice <= 0 {
                limitations.append(.navUnavailable)
            }
            if row.quantity <= 0 {
                limitations.append(.quantityUnusable)
            }
            if let pledged = row.pledgedQuantity, pledged != 0 {
                limitations.append(.pledgeRelationshipUnknown)
            }
            if !row.tradingSymbol.isEmpty, rows.enumerated().contains(where: { otherIndex, other in
                otherIndex != index && row.tradingSymbol == other.tradingSymbol
            }) {
                limitations.append(.overlappingRecords)
            }
            return MutualFundHolding(id: "mf-\(index)", fund: row.fund, symbol: row.tradingSymbol, folio: row.folio,
                                     quantity: row.quantity, averagePrice: row.averagePrice, lastPrice: row.lastPrice,
                                     navDate: row.lastPriceDate?.description, pledgedQuantity: row.pledgedQuantity, limitations: limitations)
        }
    }
}
