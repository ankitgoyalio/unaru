//
//  PortfolioAllocation.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

public import Foundation

/// Source-supported investment groups, without inferred security or fund exposure.
public enum HoldingInvestmentType: String, Codable, Sendable {
    /// Securities holdings do not provide a supported asset classification.
    case unknown
    /// The dedicated mutual fund holdings source establishes this group only.
    case mutualFund
}

/// Backend-authoritative concentration of the same ordinary holdings used for current value.
public struct PortfolioAllocation: Codable, Sendable {
    /// Available valued subset, zero for successful empty ordinary inventory.
    public let currentValue: Decimal?
    /// Ordinary records, including unavailable valuations and ambiguous inventory.
    public let totalHoldings: Int
    /// Ordinary records with a supported current value, independent of usable acquisition cost.
    public let valuedHoldings: Int
    /// Records with separate financing omitted, including mixed ordinary and MTF records.
    public let excludedMTFHoldings: Int
    /// All valued ordinary holdings, descending by value with source-qualified identity as a tie-breaker.
    public let largestHoldings: [PortfolioAllocationHolding]
    /// Supported groups, retaining unknown instruments and unavailable group values.
    public let groups: [PortfolioAllocationGroup]

    /// Creates the credential-free result without client-side financial calculations.
    public init(currentValue: Decimal?, totalHoldings: Int, valuedHoldings: Int, excludedMTFHoldings: Int,
                largestHoldings: [PortfolioAllocationHolding], groups: [PortfolioAllocationGroup])
    {
        self.currentValue = currentValue
        self.totalHoldings = totalHoldings
        self.valuedHoldings = valuedHoldings
        self.excludedMTFHoldings = excludedMTFHoldings
        self.largestHoldings = largestHoldings
        self.groups = groups
    }
}

/// A ranked, valued holding; unavailable rows remain in the source and performance projections.
public struct PortfolioAllocationHolding: Codable, Sendable, Identifiable {
    /// Source-qualified row identity, never a symbol-only merge.
    public var id: String {
        source.rawValue + ":" + sourceRowID
    }

    /// Source of the supported ordinary inventory.
    public let source: PortfolioHoldingPerformance.Source
    /// Original source-local identity for inspection.
    public let sourceRowID: String
    /// Source-provided name or symbol, without an external lookup.
    public let name: String
    /// Classification supported by the source, preserving unknown securities.
    public let investmentType: HoldingInvestmentType
    /// Ordinary current value, excluding any financed component.
    public let currentValue: Decimal
    /// Share of the positive valued total, times 100; unavailable for a nonpositive total.
    public let allocationPercent: Decimal?

    /// Creates a ranked entry calculated by Backend.
    public init(source: PortfolioHoldingPerformance.Source, sourceRowID: String, name: String, investmentType: HoldingInvestmentType,
                currentValue: Decimal, allocationPercent: Decimal?)
    {
        self.source = source
        self.sourceRowID = sourceRowID
        self.name = name
        self.investmentType = investmentType
        self.currentValue = currentValue
        self.allocationPercent = allocationPercent
    }
}

/// One mutually exclusive group of ordinary holdings, including its unvalued records.
public struct PortfolioAllocationGroup: Codable, Sendable, Identifiable {
    /// The supported type is unique within an allocation result.
    public var id: String {
        investmentType.rawValue
    }

    /// Unknown is retained without treating exchange listings as equity or inferring ETF exposure.
    public let investmentType: HoldingInvestmentType
    /// Sum of available group values; unavailable when none of the group's holdings can be valued.
    public let currentValue: Decimal?
    /// Group share of the same positive valued total used for individual holdings.
    public let allocationPercent: Decimal?
    /// Ordinary records in the group, including unavailable valuations.
    public let totalHoldings: Int
    /// Group records with supported current value.
    public let valuedHoldings: Int

    /// Creates a group without combining overlapping sources or financial populations.
    public init(investmentType: HoldingInvestmentType, currentValue: Decimal?, allocationPercent: Decimal?, totalHoldings: Int, valuedHoldings: Int) {
        self.investmentType = investmentType
        self.currentValue = currentValue
        self.allocationPercent = allocationPercent
        self.totalHoldings = totalHoldings
        self.valuedHoldings = valuedHoldings
    }
}
