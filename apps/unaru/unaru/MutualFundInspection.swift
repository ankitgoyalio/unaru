//
//  MutualFundInspection.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Shared
    import SwiftUI

    /// Broker-reported units, prices and dates with explicit limits on their interpretation.
    struct MutualFundInspection: View {
        /// Source row retained without merging matching fund symbols or folios.
        let holding: MutualFundHolding
        /// Final cross-source eligibility, when both sources have been analysed.
        let analysis: PortfolioHoldingPerformance?
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mutual Fund Details").font(.title).accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HoldingPerformanceView(performance: analysis?.values ?? holding.performance, overlapsSources: analysis?.overlapsSources == true)
                        GroupBox("Identity and Source") {
                            fields {
                                field("Fund", holding.fund)
                                field("Symbol / ISIN", holding.symbol.isEmpty ? "Unavailable" : holding.symbol)
                                field("Folio", holding.folio.flatMap { $0.isEmpty ? nil : $0 } ?? "Unavailable")
                                field("Source", "Kite mutual fund holdings")
                                field("Source row", holding.id)
                            }
                        }
                        GroupBox("Units and Prices — Broker Reported") {
                            fields {
                                field("Units", mutualFundDecimal(holding.quantity))
                                field("Pledged units", holding.pledgedQuantity.map(mutualFundDecimal) ?? "Unavailable")
                                field("Average acquisition price", holding.averagePrice > 0 ? mutualFundDecimal(holding.averagePrice) : "Unavailable")
                                field("Latest NAV", holding.lastPrice > 0 ? mutualFundDecimal(holding.lastPrice) : "Unavailable")
                                field("NAV date", holding.navDate ?? "Unavailable")
                                if holding.averagePrice <= 0 {
                                    field("Reported acquisition price", mutualFundDecimal(holding.averagePrice))
                                }
                                if holding.lastPrice <= 0 {
                                    field("Reported NAV", mutualFundDecimal(holding.lastPrice))
                                }
                                Text("Prices in INR. NAV date is separate from source retrieval time.").foregroundStyle(.secondary)
                            }
                        }
                        if !holding.limitations.isEmpty {
                            GroupBox("Data Limitations") {
                                fields {
                                    ForEach(holding.limitations, id: \.rawValue) { Text($0.description) }
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

    private extension MutualFundHolding.Limitation {
        var description: String {
            switch self {
            case .navDateUnavailable: "NAV date unavailable"
            case .acquisitionPriceUnavailable: "Acquisition cost unavailable"
            case .navUnavailable: "NAV unavailable"
            case .quantityUnusable: "Units unavailable for valuation"
            case .pledgeRelationshipUnknown: "Pledge relationship unavailable"
            case .overlappingRecords: "Potentially overlapping records — no combined contribution"
            }
        }
    }
#endif
