//
//  HoldingInspection.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Broker fields stay inspectable without implying an investment calculation or price date.
    struct HoldingInspection: View {
        /// The selected source row, including separate financing metadata.
        let holding: SecurityHolding
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Holding Details").font(.title).accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Identity and Source") {
                            fields {
                                field("Symbol", holding.symbol)
                                field("Name", holding.name ?? "Name unavailable")
                                field("Investment type", "Unknown investment type")
                                field("Exchange", holding.exchange)
                                field("ISIN", holding.isin.isEmpty ? "Unavailable" : holding.isin)
                                field("Instrument token", String(holding.instrumentToken))
                                field("Product", holding.product)
                                field("Source", "Kite securities holdings")
                                field("Source row", holding.id)
                            }
                        }
                        GroupBox("Quantities — Broker Reported") {
                            fields {
                                field("Ordinary quantity (Kite)", String(holding.quantity))
                                field("T1 quantity", String(holding.t1Quantity))
                                field("Realised quantity", String(holding.realisedQuantity))
                                field("Opening quantity", String(holding.openingQuantity))
                                field("Used quantity", holding.usedQuantity.map(String.init) ?? "Unavailable")
                                field("Authorised quantity", String(holding.authorisedQuantity))
                                field("Short quantity", holding.shortQuantity.map(String.init) ?? "Unavailable")
                                field("Collateral quantity", String(holding.collateralQuantity))
                                field("Collateral type", holding.collateralType.flatMap { $0.isEmpty ? nil : $0 } ?? "Unavailable")
                            }
                        }
                        GroupBox("Prices") {
                            fields {
                                field("Average acquisition price", usablePrice(holding.averagePrice))
                                field("Market price", usablePrice(holding.lastPrice))
                                Text("Price valuation date unavailable").foregroundStyle(.secondary)
                                if holding.averagePrice <= 0 {
                                    field("Reported acquisition price", reportedDecimal(holding.averagePrice))
                                }
                                if holding.lastPrice <= 0 {
                                    field("Reported market price", reportedDecimal(holding.lastPrice))
                                }
                            }
                        }
                        if let mtf = holding.mtf {
                            GroupBox("MTF — Broker Reported") {
                                fields {
                                    field("Financed quantity", String(mtf.quantity))
                                    field("MTF used quantity", String(mtf.usedQuantity))
                                    field("MTF average acquisition price", reportedDecimal(mtf.averagePrice))
                                    field("Gross value", reportedDecimal(mtf.value))
                                    field("Initial margin", reportedDecimal(mtf.initialMargin))
                                    Text("Separate from ordinary holdings. Gross value and initial margin do not establish financing-adjusted returns.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !holding.limitations.isEmpty {
                            GroupBox("Data Limitations") {
                                fields {
                                    ForEach(holding.limitations, id: \.rawValue) { limitation in
                                        Text(limitation.description)
                                    }
                                }
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

        /// Aligned native labels retain text selection and wrap long provider values.
        private func field(_ label: String, _ value: String) -> some View {
            LabeledContent(label) {
                Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }

        private func fields(@ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 10, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    /// Display rounding never changes the source Decimal or performs binary floating-point arithmetic.
    func usablePrice(_ value: Decimal) -> String {
        value > 0 ? value.formatted(.currency(code: "INR")) : "Unavailable"
    }

    /// Inspection can expose an unusable raw value without treating it as a usable zero.
    private func reportedDecimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private extension SecurityHolding.Limitation {
        var description: String {
            switch self {
            case .nameUnavailable: "Name unavailable"
            case .classificationUnavailable: "Investment classification unavailable"
            case .valuationDateUnavailable: "Price valuation date unavailable"
            case .acquisitionPriceUnavailable: "Acquisition cost unavailable"
            case .marketPriceUnavailable: "Market price unavailable"
            case .quantityUnusable: "Ordinary quantity unavailable for valuation"
            case .collateralRelationshipUnknown: "Collateral relationship unavailable"
            case .mtfRelationshipUnknown: "MTF sale reconciliation unavailable"
            case .overlappingRecords: "Potentially overlapping records — no combined contribution"
            case .discrepancy: "Kite reports a holding discrepancy"
            }
        }
    }
#endif
