//
//  PerformanceTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import NIOCore
import Shared
import Testing
import Vapor
import VaporTesting

@Suite("Authoritative current-holdings performance over HTTP")
struct PerformanceTests {
    let authorization = KiteLoginTests().authorization

    @Test("Settled plus T1 retains ordinary mixed MTF inventory without deducting a same-day sale twice")
    func ordinaryInventory() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([ordinaryFixture([
            "quantity": 60, "t1_quantity": 5, "used_quantity": 40,
            "mtf": ["quantity": 10, "used_quantity": 0, "average_price": 50, "value": 1500, "initial_margin": 300],
        ])]))
        try await transport.setPositions(body: positionsPayload(net: [
            positionFixture(["tradingsymbol": "STOCK", "product": "CNC", "quantity": -40]),
            positionFixture(["tradingsymbol": "PURCHASE-ONLY", "product": "CNC", "quantity": 20]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            _ = try await app.testing().sendRequest(.GET, "portfolio/positions", headers: authorization)
            let response = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            let rows = try #require(json["holdings"] as? [[String: Any]])
            let values = try #require(rows[0]["performance"] as? [String: Any])
            #expect(values["quantity"] as? Int == 65)
            #expect(values["investedCost"] as? Int == 6500)
            #expect(values["currentValue"] as? Int == 7800)
            #expect(values["gain"] as? Int == 1300)
            #expect(values["returnPercent"] as? Int == 20)
        }
    }

    @Test("Unequal securities and fractional funds use matched cost and gain for a weighted combined percentage")
    func combinedPerformance() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([ordinaryFixture()]))
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(["quantity": 2.5, "average_price": 40, "last_price": 80, "pledged_quantity": 0]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            #expect(response.status == .ok)
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            #expect(json["investedCost"] as? Int == 1100)
            #expect(json["currentValue"] as? Int == 1400)
            #expect(json["gain"] as? Int == 300)
            let result = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            let percent = try #require(result.returnPercent)
            #expect(percent > Decimal(string: "27.27272727272727")! && percent < Decimal(string: "27.27272727272728")!)
            #expect(json["matchedCost"] as? Int == 1100)
            #expect(json["totalHoldings"] as? Int == 2)
            #expect(json["valueCount"] as? Int == 2)
            #expect(json["returnCount"] as? Int == 2)
            #expect(response.headers["Cache-Control"] == ["no-store"])
            #expect(!response.body.string.contains("test-access"))
        }
    }

    @Test("Coverage separates cost, value and matched returns; MTF-only, ambiguous and unavailable rows stay inspectable")
    func partialCoverage() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([
            ordinaryFixture(["tradingsymbol": "ZERO-GAIN", "isin": "A", "last_price": 100]),
            ordinaryFixture(["tradingsymbol": "NO-COST", "isin": "B", "average_price": 0]),
            ordinaryFixture(["tradingsymbol": "NO-PRICE", "isin": "C", "last_price": 0]),
            ordinaryFixture(["tradingsymbol": "MTF-ONLY", "isin": "D", "quantity": 0,
                             "mtf": ["quantity": 20, "used_quantity": 0, "average_price": 30, "value": 600, "initial_margin": 100]]),
            ordinaryFixture(["tradingsymbol": "SHORT", "isin": "E", "short_quantity": 2]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let rows = try securities.content.decode(SecuritiesHoldings.self, using: JSONDecoder()).holdings
            #expect(rows.count == 5)
            #expect(rows[0].performance?.gain == 0)
            #expect(rows[0].performance?.returnPercent == 0)
            #expect(rows[1].performance?.investedCost == nil)
            #expect(rows[1].performance?.currentValue == 1200)
            #expect(rows[1].performance?.gain == nil)
            #expect(rows[2].performance?.investedCost == 1000)
            #expect(rows[2].performance?.currentValue == nil)
            #expect(rows[3].performance?.excludedMTFOnly == true)
            #expect(rows[3].mtf?.value == 600)
            #expect(rows[4].performance?.currentValue == nil)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            #expect(total.investedCost == 2000)
            #expect(total.currentValue == 2200)
            #expect(total.gain == 0)
            #expect(total.returnPercent == 0)
            #expect(total.matchedCost == 1000)
            #expect(total.totalHoldings == 4)
            #expect(total.costCount == 2)
            #expect(total.valueCount == 2)
            #expect(total.returnCount == 1)
            #expect(total.excludedMTFCount == 1)
        }
    }
}

/// Ordinary source fixture with documented primary quantities and no ambiguous collateral or financing sales.
func ordinaryFixture(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var row = holdingFixture(["quantity": 10, "t1_quantity": 0, "used_quantity": 0, "short_quantity": 0,
                              "collateral_quantity": 0, "average_price": 100, "last_price": 120, "mtf": NSNull()])
    row.merge(overrides) { _, new in new }
    return row
}

/// Requests aggregation of exactly the source reads observed by this HTTP client.
func requestPerformance(_ app: Application, securities: String, funds: String) async throws -> TestingHTTPResponse {
    let left = try JSONSerialization.jsonObject(with: Data(securities.utf8)) as? [String: Any]
    let right = try JSONSerialization.jsonObject(with: Data(funds.utf8)) as? [String: Any]
    let request = ["securitiesReadID": left?["readID"] as? String ?? "missing", "mutualFundsReadID": right?["readID"] as? String ?? "missing"]
    let data = try JSONSerialization.data(withJSONObject: request)
    return try await app.testing().sendRequest(.POST, "portfolio/performance", headers: KiteLoginTests().authorization, body: .init(bytes: data))
}
