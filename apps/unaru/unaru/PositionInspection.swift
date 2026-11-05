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
                            fields {
                                field("Symbol", position.symbol)
                                field("Exchange", position.exchange)
                                field("Product", position.product)
                                field("Instrument token", String(position.instrumentToken))
                                field("Source", "Kite net positions")
                                field("Source row", position.id)
                                field("Status", position.state == .closed ? "Closed" : "Current")
                                field("Signed net quantity", String(position.quantity))
                                field("Overnight quantity", String(position.overnightQuantity))
                                field("Multiplier", position.multiplier.formatted())
                            }
                        }
                        GroupBox("Prices and Trading P&L") {
                            fields {
                                field("Average price", usablePrice(position.averagePrice))
                                field("Last price", usablePrice(position.lastPrice))
                                field("Previous close", usablePrice(position.closePrice))
                                Text("Price valuation date unavailable").foregroundStyle(.secondary)
                                field("Realised trading P&L", tradingPnL(position.realised))
                                field("Unrealised trading P&L", tradingPnL(position.unrealised))
                                field("Total trading P&L", tradingPnL(position.pnl))
                                field("Mark-to-market P&L", tradingPnL(position.m2m))
                                field("Position value (Kite)", currency(position.value))
                                Text("Trading P&L is separate from holdings returns.").foregroundStyle(.secondary)
                            }
                        }
                        GroupBox("Buy and Sell Activity — Broker Reported") {
                            fields {
                                field("Buy quantity", String(position.buyQuantity))
                                field("Buy average price", currency(position.buyPrice))
                                field("Buy value", currency(position.buyValue))
                                field("Buy mark-to-market value", currency(position.buyM2M))
                                field("Sell quantity", String(position.sellQuantity))
                                field("Sell average price", currency(position.sellPrice))
                                field("Sell value", currency(position.sellValue))
                                field("Sell mark-to-market value", currency(position.sellM2M))
                                field("Day buy quantity", String(position.dayBuyQuantity))
                                field("Day buy average price", currency(position.dayBuyPrice))
                                field("Day buy value", currency(position.dayBuyValue))
                                field("Day sell quantity", String(position.daySellQuantity))
                                field("Day sell average price", currency(position.daySellPrice))
                                field("Day sell value", currency(position.daySellValue))
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

        /// Native labels wrap and allow copying broker-reported values.
        private func field(_ label: String, _ value: String) -> some View {
            LabeledContent(label) {
                Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }

        /// Groups remain readable in the scrolling inspection sheet.
        private func fields(@ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 10, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
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
