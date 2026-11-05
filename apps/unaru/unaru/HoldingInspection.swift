//
//  HoldingInspection.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared
    import SwiftUI

    /// Broker fields and authoritative current-holdings values stay inspectable with their limitations.
    struct HoldingInspection: View {
        @EnvironmentObject private var connection: BackendConnection
        /// Observes source recovery even when another window starts the refresh.
        @ObservedObject var store: PortfolioStore
        /// The selected source row, including separate financing metadata.
        let holding: SecurityHolding
        /// Final cross-source eligibility, when both sources have been analysed.
        let analysis: PortfolioHoldingPerformance?
        /// Allocation requires a current combined denominator, even when stale source values remain inspectable.
        let allocationIsCurrent: Bool
        /// The exact selected source retrieval, separate from its price or NAV date.
        let retrievedAt: Date
        /// Available broker price date, never inferred from retrieval time.
        let valuationDate: String?
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Holding Details").font(.title).accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SourceInspectionStatus(source: "Securities holdings", isLoading: store.isLoading,
                                               failed: store.failed, retrievedAt: retrievedAt,
                                               retryTitle: "Retry Securities") { connection.refreshPortfolio(source: .securities) }
                        HoldingPerformanceView(performance: analysis?.values ?? holding.performance, overlapsSources: analysis?.overlapsSources == true,
                                               allocationPercent: allocationIsCurrent ? analysis?.allocationPercent : nil)
                        GroupBox("Identity and Source") {
                            inspectionFields {
                                inspectionField("Symbol", holding.symbol)
                                inspectionField("Name", holding.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Name unavailable")
                                inspectionField("Investment type", "Unknown investment type")
                                inspectionField("Exchange", holding.exchange)
                                inspectionField("ISIN", holding.isin.isEmpty ? "Unavailable" : holding.isin)
                                inspectionField("Instrument token", String(holding.instrumentToken))
                                inspectionField("Product", holding.product)
                                inspectionField("Source", "Kite securities holdings")
                                inspectionField("Source row", holding.id)
                            }
                        }
                        GroupBox("Quantities — Broker Reported") {
                            inspectionFields {
                                inspectionField("Ordinary quantity (Kite)", String(holding.quantity))
                                inspectionField("T1 quantity", String(holding.t1Quantity))
                                inspectionField("Realised quantity", String(holding.realisedQuantity))
                                inspectionField("Opening quantity", String(holding.openingQuantity))
                                inspectionField("Used quantity", holding.usedQuantity.map(String.init) ?? "Unavailable")
                                inspectionField("Authorised quantity", String(holding.authorisedQuantity))
                                inspectionField("Short quantity", holding.shortQuantity.map(String.init) ?? "Unavailable")
                                inspectionField("Collateral quantity", String(holding.collateralQuantity))
                                inspectionField("Collateral type", holding.collateralType.flatMap { $0.isEmpty ? nil : $0 } ?? "Unavailable")
                            }
                        }
                        GroupBox("Prices") {
                            inspectionFields {
                                inspectionField("Average acquisition price", usablePrice(holding.averagePrice))
                                inspectionField("Market price", usablePrice(holding.lastPrice))
                                LabeledContent("Price valuation date") {
                                    Text(valuationDate ?? "Unavailable").accessibilityIdentifier("Holding valuation date")
                                }
                                if valuationDate == nil {
                                    Text("Price valuation date unavailable").foregroundStyle(.secondary)
                                }
                                if holding.averagePrice <= 0 {
                                    inspectionField("Reported acquisition price", reportedDecimal(holding.averagePrice))
                                }
                                if holding.lastPrice <= 0 {
                                    inspectionField("Reported market price", reportedDecimal(holding.lastPrice))
                                }
                            }
                        }
                        if let mtf = holding.mtf {
                            GroupBox("MTF — Broker Reported") {
                                inspectionFields {
                                    inspectionField("Financed quantity", String(mtf.quantity))
                                    inspectionField("MTF used quantity", String(mtf.usedQuantity))
                                    inspectionField("MTF average acquisition price", reportedDecimal(mtf.averagePrice))
                                    inspectionField("Gross value", reportedDecimal(mtf.value))
                                    inspectionField("Initial margin", reportedDecimal(mtf.initialMargin))
                                    Text("Separate from ordinary holdings. Gross value and initial margin do not establish financing-adjusted returns.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !holding.limitations.isEmpty {
                            GroupBox("Data Limitations") {
                                inspectionFields {
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
