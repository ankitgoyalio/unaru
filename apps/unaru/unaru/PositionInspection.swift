//
//  PositionInspection.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Raw broker details explain trading exposure without calculating investment returns.
    struct PositionInspection: View {
        @EnvironmentObject private var connection: BackendConnection
        /// Observes the retained source rather than treating an open row as newly retrieved.
        @ObservedObject var store: PositionsStore
        /// One row of the net collection at the displayed retrieval.
        let position: TradingPosition
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Position Details").font(.title).accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SourceInspectionStatus(source: "Positions", isLoading: store.isLoading,
                                               failed: store.failed, retrievedAt: store.snapshot?.retrievedAt,
                                               retryTitle: "Retry Positions") { connection.refreshPositions() }
                        GroupBox("Identity and Exposure") {
                            inspectionFields {
                                inspectionField("Symbol", position.symbol, fillsTrailingColumn: true)
                                inspectionField("Exchange", position.exchange, fillsTrailingColumn: true)
                                inspectionField("Product", position.product, fillsTrailingColumn: true)
                                inspectionField("Instrument token", String(position.instrumentToken), fillsTrailingColumn: true)
                                inspectionField("Source", "Kite net positions", fillsTrailingColumn: true)
                                inspectionField("Source row", position.id, fillsTrailingColumn: true)
                                inspectionField("Status", position.state == .closed ? "Closed" : "Current", fillsTrailingColumn: true)
                                inspectionField("Signed net quantity", String(position.quantity), fillsTrailingColumn: true)
                                inspectionField("Overnight quantity", String(position.overnightQuantity), fillsTrailingColumn: true)
                                inspectionField("Multiplier", position.multiplier.formatted(), fillsTrailingColumn: true)
                            }
                        }
                        GroupBox("Prices and Trading P&L") {
                            inspectionFields {
                                inspectionField("Average price", usablePrice(position.averagePrice), fillsTrailingColumn: true)
                                inspectionField("Last price", usablePrice(position.lastPrice), fillsTrailingColumn: true)
                                inspectionField("Previous close", usablePrice(position.closePrice), fillsTrailingColumn: true)
                                Text("Price valuation date unavailable").foregroundStyle(.secondary)
                                inspectionField("Realised trading P&L", tradingPnL(position.realised), fillsTrailingColumn: true)
                                inspectionField("Unrealised trading P&L", tradingPnL(position.unrealised), fillsTrailingColumn: true)
                                inspectionField("Total trading P&L", tradingPnL(position.pnl), fillsTrailingColumn: true)
                                inspectionField("Mark-to-market P&L", tradingPnL(position.m2m), fillsTrailingColumn: true)
                                inspectionField("Position value (Kite)", currency(position.value), fillsTrailingColumn: true)
                                Text("Trading P&L is separate from holdings returns.").foregroundStyle(.secondary)
                            }
                        }
                        GroupBox("Buy and Sell Activity — Broker Reported") {
                            inspectionFields {
                                inspectionField("Buy quantity", String(position.buyQuantity), fillsTrailingColumn: true)
                                inspectionField("Buy average price", currency(position.buyPrice), fillsTrailingColumn: true)
                                inspectionField("Buy value", currency(position.buyValue), fillsTrailingColumn: true)
                                inspectionField("Buy mark-to-market value", currency(position.buyM2M), fillsTrailingColumn: true)
                                inspectionField("Sell quantity", String(position.sellQuantity), fillsTrailingColumn: true)
                                inspectionField("Sell average price", currency(position.sellPrice), fillsTrailingColumn: true)
                                inspectionField("Sell value", currency(position.sellValue), fillsTrailingColumn: true)
                                inspectionField("Sell mark-to-market value", currency(position.sellM2M), fillsTrailingColumn: true)
                                inspectionField("Day buy quantity", String(position.dayBuyQuantity), fillsTrailingColumn: true)
                                inspectionField("Day buy average price", currency(position.dayBuyPrice), fillsTrailingColumn: true)
                                inspectionField("Day buy value", currency(position.dayBuyValue), fillsTrailingColumn: true)
                                inspectionField("Day sell quantity", String(position.daySellQuantity), fillsTrailingColumn: true)
                                inspectionField("Day sell average price", currency(position.daySellPrice), fillsTrailingColumn: true)
                                inspectionField("Day sell value", currency(position.daySellValue), fillsTrailingColumn: true)
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
            .frame(width: 560, height: 640)
        }

        /// Rounds only for display, retaining the source's signed Decimal value.
        private func currency(_ value: Decimal) -> String {
            value.formatted(.currency(code: "INR"))
        }
    }

    /// Explicit words convey gain and loss independently of color.
    func tradingPnL(_ value: Decimal) -> String {
        if value < 0 {
            return "Loss \((-value).formatted(.currency(code: "INR")))"
        }
        if value > 0 {
            return "Gain \(value.formatted(.currency(code: "INR")))"
        }
        return value.formatted(.currency(code: "INR"))
    }
#endif
