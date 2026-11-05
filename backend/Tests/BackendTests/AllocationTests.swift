//
//  AllocationTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import Shared
import Testing
import VaporTesting

@Suite("Current-value allocation over authenticated HTTP")
struct AllocationTests {
    let authorization = KiteLoginTests().authorization

    @Test("Unequal holdings and fractional funds rank by value, including value without cost and excluding financing")
    func currentValueAllocation() async throws {
        let transport = KiteResponses()
        try await transport.setFunds(body: fundsPayload())
        try await transport.setPositions(body: positionsPayload(net: [positionFixture(["quantity": 1000, "last_price": 500])]))
        try await transport.setHoldings(body: holdingsPayload([
            ordinaryFixture(["tradingsymbol": "SMALL-ETF", "isin": "ETF", "quantity": 1, "average_price": 1000, "last_price": 100]),
            ordinaryFixture(["tradingsymbol": "UNKNOWN", "isin": "UNKNOWN", "quantity": 5, "average_price": 0, "last_price": 100,
                             "mtf": ["quantity": 100, "used_quantity": 0, "average_price": 50, "value": 10000, "initial_margin": 1000]]),
            ordinaryFixture(["tradingsymbol": "MTF-ONLY", "isin": "MTF", "quantity": 0,
                             "mtf": ["quantity": 20, "used_quantity": 0, "average_price": 50, "value": 2000, "initial_margin": 500]]),
        ]))
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(["quantity": 2.5, "average_price": 40, "last_price": 160, "pledged_quantity": 0]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let positions = try await app.testing().sendRequest(.GET, "portfolio/positions", headers: authorization)
            let fundsContext = try await app.testing().sendRequest(.GET, "portfolio/funds", headers: authorization)
            #expect(positions.status == .ok)
            #expect(fundsContext.status == .ok)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            let allocation = try #require(json["allocation"] as? [String: Any])
            #expect(allocation["currentValue"] as? Int == 1000)
            #expect(allocation["totalHoldings"] as? Int == 3)
            #expect(allocation["valuedHoldings"] as? Int == 3)
            #expect(allocation["excludedMTFHoldings"] as? Int == 2)
            let ranked = try #require(allocation["largestHoldings"] as? [[String: Any]])
            #expect(ranked.compactMap { $0["name"] as? String } == ["UNKNOWN", "Sample Growth Fund", "SMALL-ETF"])
            #expect(ranked.compactMap { $0["allocationPercent"] as? Int } == [50, 40, 10])
            #expect(ranked.compactMap { $0["investmentType"] as? String } == ["unknown", "mutualFund", "unknown"])
            let groups = try #require(allocation["groups"] as? [[String: Any]])
            #expect(groups.compactMap { $0["investmentType"] as? String } == ["unknown", "mutualFund"])
            #expect(groups.compactMap { $0["currentValue"] as? Int } == [600, 400])
            #expect(groups.compactMap { $0["allocationPercent"] as? Int } == [60, 40])
            let rows = try #require(json["rows"] as? [[String: Any]])
            #expect(rows.compactMap { $0["allocationPercent"] as? Int } == [10, 50, 40])
            #expect(response.headers["Cache-Control"] == ["no-store"])
            #expect(!response.body.string.contains("test-access"))
        }
    }
}
