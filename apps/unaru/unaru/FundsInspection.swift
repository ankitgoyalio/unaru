//
//  FundsInspection.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Inspectable broker components retain their meanings without additive totals.
    struct FundsInspection: View {
        @EnvironmentObject private var connection: BackendConnection
        /// Tracks this supporting source independently of holdings and positions.
        @ObservedObject var store: FundsStore
        /// One enabled segment from the current source snapshot.
        let segment: TradingFundsSegment
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(segment.displayName) Funds Details").font(.title).accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SourceInspectionStatus(source: "Trading funds", isLoading: store.isLoading,
                                               failed: store.failed, retrievedAt: store.snapshot?.retrievedAt,
                                               retryTitle: "Retry Funds") { connection.refreshFunds() }
                        Text("Broker-reported components overlap. Cash includes intraday pay-in; collateral is margin from pledged securities. These amounts are not additional investment wealth.")
                            .foregroundStyle(.secondary)
                        GroupBox("Availability Components") {
                            components(segment.availableComponents, labels: [
                                ("cash", "Cash (includes intraday pay-in)"), ("openingBalance", "Opening balance"),
                                ("liveBalance", "Live balance"), ("intradayPayin", "Intraday pay-in"),
                                ("adhocMargin", "Additional broker margin"), ("collateral", "Collateral margin"),
                            ])
                        }
                        GroupBox("Utilisation Components") {
                            components(segment.utilisedComponents, labels: [
                                ("debits", "Total utilised margin"), ("m2mUnrealised", "Unrealised intraday P&L"),
                                ("m2mRealised", "Realised intraday P&L"), ("span", "SPAN margin"),
                                ("optionPremium", "Option premium"), ("holdingSales", "Holding sales"),
                                ("exposure", "Exposure margin"), ("liquidCollateral", "Liquid collateral utilised"),
                                ("delivery", "Delivery margin"), ("stockCollateral", "Stock collateral utilised"),
                                ("turnover", "Turnover utilised"), ("payout", "Payout"),
                            ])
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(24).frame(width: 560, height: 640)
        }

        /// Stable broker-field ordering and native label/value accessibility.
        private func components(_ values: [String: Decimal], labels: [(String, String)]) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(labels, id: \.0) { key, label in
                    LabeledContent(label) {
                        Text(values[key].map(fundsAmount) ?? "Unavailable").textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    extension TradingFundsSegment {
        /// Native destination terminology for supported broker segments.
        var displayName: String {
            switch segment {
            case "equity": "Equity"
            case "commodity": "Commodity"
            default: segment
            }
        }
    }

    /// Currency formatting preserves signed and zero balances without changing source precision.
    func fundsAmount(_ value: Decimal) -> String {
        value.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
    }
#endif
