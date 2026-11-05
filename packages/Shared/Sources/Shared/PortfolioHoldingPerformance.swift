//
//  PortfolioHoldingPerformance.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

/// A source-qualified valuation used consistently by combined analysis and holding inspection.
public struct PortfolioHoldingPerformance: Codable, Sendable, Identifiable {
    /// Stable within this pair of source reads; source prefixes prevent row-ID collisions.
    public var id: String {
        source.rawValue + ":" + sourceRowID
    }

    /// The original holdings source; positions and funds never enter this projection.
    public let source: Source
    /// The source-local row identity, without an assumed symbol-only relationship.
    public let sourceRowID: String
    /// Final backend eligibility and values, including cross-source overlap exclusions.
    public let values: HoldingPerformance
    /// Both records remain inspectable when depository identity could represent the same inventory.
    public let overlapsSources: Bool

    /// Supported contributing holdings sources.
    public enum Source: String, Codable, Sendable {
        /// Exchange-traded securities, without an invented asset classification.
        case securities
        /// Mutual fund units from the separate fund holdings source.
        case mutualFunds
    }

    /// Creates a projection without merging or removing source rows.
    public init(source: Source, sourceRowID: String, values: HoldingPerformance, overlapsSources: Bool) {
        self.source = source
        self.sourceRowID = sourceRowID
        self.values = values
        self.overlapsSources = overlapsSources
    }
}
