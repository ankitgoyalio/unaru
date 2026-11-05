//
//  AllocationCoverageTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import Shared
import Testing
import VaporTesting

extension AllocationTests {
    @Test("Unavailable and cross-source ambiguous values remain visible in incomplete type coverage")
    func incompleteCoverage() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([
            ordinaryFixture(["isin": "VALUED", "quantity": 1, "last_price": 100]),
            ordinaryFixture(["tradingsymbol": "NO-PRICE", "isin": "NO-PRICE", "last_price": 0]),
            ordinaryFixture(["tradingsymbol": "AMBIGUOUS", "isin": "SHARED"]),
        ]))
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(["tradingsymbol": "SHARED", "pledged_quantity": 0]),
            mutualFundHoldingFixture(["tradingsymbol": "NO-NAV", "last_price": 0, "pledged_quantity": 0]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            let allocation = try #require(total.allocation)
            #expect(allocation.currentValue == 100)
            #expect(allocation.valuedHoldings == 1)
            #expect(allocation.totalHoldings == 5)
            #expect(allocation.largestHoldings.map(\.name) == ["STOCK"])
            #expect(allocation.largestHoldings.first?.allocationPercent == 100)
            #expect(total.rows?.count == 5)
            #expect(total.rows?.compactMap(\.allocationPercent) == [100])
            #expect(allocation.groups.map(\.totalHoldings) == [3, 2])
            #expect(allocation.groups.map(\.valuedHoldings) == [1, 0])
            #expect(allocation.groups.first?.currentValue == 100)
            #expect(allocation.groups.last?.currentValue == nil)
            #expect(allocation.groups.last?.allocationPercent == nil)
        }
    }

    @Test("Nonpositive source inputs never establish an allocation denominator", arguments: [0, -1])
    func noValuedDenominator(input: Int) async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([ordinaryFixture(["last_price": input])]))
        try await transport.setMutualFunds(body: holdingsPayload([mutualFundHoldingFixture(["quantity": input, "pledged_quantity": 0])]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            let allocation = try #require(total.allocation)
            #expect(allocation.currentValue == nil)
            #expect(allocation.totalHoldings == 2)
            #expect(allocation.valuedHoldings == 0)
            #expect(allocation.largestHoldings.isEmpty)
            #expect(allocation.groups.allSatisfy { $0.currentValue == nil && $0.allocationPercent == nil })
            #expect(total.rows?.allSatisfy { $0.allocationPercent == nil } == true)
        }
    }

    @Test("Successful empty sources report zero ordinary inventory without invented weights")
    func emptyAllocation() async throws {
        try await sessionApp(IsolatedSessionStore(), transport: KiteResponses()) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            let allocation = try #require(total.allocation)
            #expect(allocation.currentValue == 0)
            #expect(allocation.totalHoldings == 0)
            #expect(allocation.valuedHoldings == 0)
            #expect(allocation.groups.isEmpty)
            #expect(allocation.largestHoldings.isEmpty)
        }
    }
}
