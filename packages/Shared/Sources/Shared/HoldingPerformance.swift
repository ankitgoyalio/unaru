//
//  HoldingPerformance.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

public import Foundation

/// Backend-calculated ordinary holding values. Nil is unavailable, distinct from a legitimate zero.
public struct HoldingPerformance: Codable, Sendable {
    /// Usable ordinary inventory, including T1 and excluding financed units.
    public let quantity: Decimal?
    /// Acquisition cost, independent of market-price availability.
    public let investedCost: Decimal?
    /// Available market value, independent of acquisition-cost availability.
    public let currentValue: Decimal?
    /// Current value minus cost for the same inventory.
    public let gain: Decimal?
    /// Gain as a percent of positive invested cost, never annualised.
    public let returnPercent: Decimal?
    /// MTF-only rows remain inspectable but are outside ordinary coverage.
    public let excludedMTFOnly: Bool

    /// Creates authoritative values without calculating in the client.
    public init(quantity: Decimal?, investedCost: Decimal?, currentValue: Decimal?, gain: Decimal?, returnPercent: Decimal?, excludedMTFOnly: Bool = false) {
        self.quantity = quantity
        self.investedCost = investedCost
        self.currentValue = currentValue
        self.gain = gain
        self.returnPercent = returnPercent
        self.excludedMTFOnly = excludedMTFOnly
    }
}
