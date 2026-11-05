//
//  PortfolioPerformance.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

public import Foundation

/// Identifies exactly the two successful source reads accepted by the app's current refresh.
public struct PortfolioPerformanceRequest: Codable, Sendable {
    /// The securities retrieval, never a broker credential.
    public let securitiesReadID: String
    /// The mutual fund retrieval, never a broker credential.
    public let mutualFundsReadID: String

    /// Requests aggregation without sending client-calculated financial inputs.
    public init(securitiesReadID: String, mutualFundsReadID: String) {
        self.securitiesReadID = securitiesReadID
        self.mutualFundsReadID = mutualFundsReadID
    }
}

/// Backend-authoritative performance for exactly two successful holdings reads.
public struct PortfolioPerformance: Codable, Sendable {
    /// Source identities let clients reject a superseded aggregate response.
    public let sources: PortfolioPerformanceRequest
    /// Final per-row eligibility, suitable for value-based allocation and ordering without recalculation.
    public let rows: [PortfolioHoldingPerformance]?
    /// Value-based allocation from the same eligible ordinary inventory.
    public let allocation: PortfolioAllocation?
    /// Sum of available acquisition costs, possibly covering fewer holdings than current value.
    public let investedCost: Decimal?
    /// Sum of available ordinary holding values, including valued rows without cost.
    public let currentValue: Decimal?
    /// Sum of gains for the holdings with both cost and value.
    public let gain: Decimal?
    /// Summed matched gain divided by summed matched cost, times 100.
    public let returnPercent: Decimal?
    /// Cost for precisely the holdings included in gain and return percentage.
    public let matchedCost: Decimal?
    /// Value for precisely the holdings included in gain and return percentage.
    public let matchedValue: Decimal?
    /// Number of rows in ordinary coverage, including rows whose calculations are unavailable.
    public let totalHoldings: Int
    /// Number of ordinary rows with usable acquisition cost.
    public let costCount: Int
    /// Number of ordinary rows with usable current value.
    public let valueCount: Int
    /// Number of ordinary rows with matched usable cost and value.
    public let returnCount: Int
    /// Financed-only rows excluded from ordinary coverage; their details remain inspectable.
    public let excludedMTFCount: Int

    /// Creates an aggregate contract; all financial arithmetic belongs to the backend.
    public init(sources: PortfolioPerformanceRequest, investedCost: Decimal?, currentValue: Decimal?, gain: Decimal?, returnPercent: Decimal?,
                matchedCost: Decimal?, matchedValue: Decimal?, totalHoldings: Int, costCount: Int, valueCount: Int, returnCount: Int, excludedMTFCount: Int, rows: [PortfolioHoldingPerformance]? = nil, allocation: PortfolioAllocation? = nil)
    {
        self.allocation = allocation
        self.rows = rows
        self.sources = sources
        self.investedCost = investedCost
        self.currentValue = currentValue
        self.gain = gain
        self.returnPercent = returnPercent
        self.matchedCost = matchedCost
        self.matchedValue = matchedValue
        self.totalHoldings = totalHoldings
        self.costCount = costCount
        self.valueCount = valueCount
        self.returnCount = returnCount
        self.excludedMTFCount = excludedMTFCount
    }
}
