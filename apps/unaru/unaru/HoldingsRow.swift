//
//  HoldingsRow.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared

    /// A display row preserves its source record and retrieval rather than merging by symbol or folio.
    struct HoldingsRow: Identifiable {
        /// Exactly one broker record from the supported holdings sources.
        enum Record {
            /// Ordinary security fields retain separate MTF metadata for inspection.
            case security(SecurityHolding)
            /// Fractional fund units retain their own name, folio and NAV date.
            case mutualFund(MutualFundHolding)
        }

        /// The original source record, with no client financial calculation.
        let record: Record
        /// The source retrieval shown in inspection.
        let retrievedAt: Date
        /// Opaque identity of this source read, when supported by the helper.
        let readID: String?
        /// Available source price date, distinct from retrieval time.
        let valuationDate: String?

        /// Source qualification prevents collisions across sources; refresh clears selection even for legacy responses.
        var id: String {
            source.qualifiedID((readID ?? "legacy") + ":" + sourceRowID)
        }

        /// The authoritative source used to look up final cross-source eligibility.
        var source: PortfolioHoldingPerformance.Source {
            switch record {
            case .security: .securities
            case .mutualFund: .mutualFunds
            }
        }

        /// Provider row identity remains independent of names, symbols and nullable folios.
        var sourceRowID: String {
            switch record {
            case let .security(row): row.id
            case let .mutualFund(row): row.id
            }
        }

        /// Faithful display name, falling back to the symbol when a security name is unavailable.
        var name: String {
            switch record {
            case let .security(row): row.name.flatMap { $0.isEmpty ? nil : $0 } ?? row.symbol
            case let .mutualFund(row): row.fund
            }
        }

        /// Symbol search never depends on the presence of a display name.
        var symbol: String {
            switch record {
            case let .security(row): row.symbol
            case let .mutualFund(row): row.symbol
            }
        }

        /// Only the mutual fund source establishes a supported type; securities remain unclassified.
        var typeName: String {
            source == .mutualFunds ? "Mutual Fund" : "Unknown"
        }

        /// Values are copied from backend source or final cross-source results, never recomputed.
        func values(in store: PortfolioStore) -> HoldingPerformance? {
            switch record {
            case let .security(row): store.values(for: row)
            case let .mutualFund(row): store.values(for: row)
            }
        }
    }
#endif
