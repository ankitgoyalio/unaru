//
//  PerformanceEligibilityTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import Shared
import Testing
import VaporTesting

extension PerformanceTests {
    @Test("Nonpositive inputs never fabricate costs, values or percentages", arguments: [0, -1])
    func unavailableInputs(input: Int) async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([
            ordinaryFixture(["quantity": input]),
            ordinaryFixture(["tradingsymbol": "GAPS", "isin": "GAPS", "average_price": input, "last_price": input]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            #expect(total.totalHoldings == 2)
            #expect(total.investedCost == nil)
            #expect(total.currentValue == nil)
            #expect(total.gain == nil)
            #expect(total.returnPercent == nil)
            #expect(total.valueCount == 0)
            #expect(total.returnCount == 0)
        }
    }

    @Test("Successful empty holdings are zero inventory with no return denominator")
    func emptyPerformance() async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            #expect(total.totalHoldings == 0)
            #expect(total.investedCost == 0)
            #expect(total.currentValue == 0)
            #expect(total.gain == 0)
            #expect(total.returnPercent == nil)
        }
    }

    @Test("Pledged, discrepant, financed-sale and overlapping records remain inspectable without contributions")
    func ambiguousInventory() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([
            ordinaryFixture(["collateral_quantity": 2]),
            ordinaryFixture(["tradingsymbol": "OTHER", "exchange": "BSE"]),
            ordinaryFixture(["tradingsymbol": "SALE", "isin": "SALE", "mtf": ["quantity": 10, "used_quantity": 1, "average_price": 50, "value": 500, "initial_margin": 100]]),
            ordinaryFixture(["tradingsymbol": "DISCREPANCY", "isin": "DISCREPANCY", "discrepancy": true]),
        ]))
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(),
            mutualFundHoldingFixture(["folio": "ANOTHER", "pledged_quantity": 0]),
            mutualFundHoldingFixture(["tradingsymbol": "PLEDGED", "pledged_quantity": 1]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let rows = try securities.content.decode(SecuritiesHoldings.self, using: JSONDecoder()).holdings
            let mf = try funds.content.decode(MutualFundHoldings.self, using: JSONDecoder()).holdings
            #expect(rows.count == 4)
            #expect(mf.count == 3)
            #expect(rows.allSatisfy { $0.performance?.quantity == nil && $0.performance?.investedCost == nil && $0.performance?.currentValue == nil })
            #expect(mf.allSatisfy { $0.performance?.quantity == nil && $0.performance?.gain == nil })
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            #expect(total.totalHoldings == 7)
            #expect(total.currentValue == nil)
            #expect(total.investedCost == nil)
            #expect(total.returnCount == 0)
        }
    }

    @Test("Fractional precision and different NAV dates survive the real SDK and authoritative valuations")
    func fractionalPrecision() async throws {
        let transport = KiteResponses()
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(["pledged_quantity": 0]),
            mutualFundHoldingFixture(["tradingsymbol": "SECOND", "pledged_quantity": 0, "last_price_date": "2026-11-02"]),
            mutualFundHoldingFixture(["tradingsymbol": "MISSING-DATE", "pledged_quantity": 0, "last_price_date": NSNull()]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let rows = try response.content.decode(MutualFundHoldings.self, using: JSONDecoder()).holdings
            #expect(rows[0].performance?.investedCost == Decimal(string: "520.042671717142508889"))
            #expect(rows[0].performance?.currentValue == Decimal(string: "543.057455855251181221"))
            #expect(rows[0].performance?.gain == Decimal(string: "23.014784138108672332"))
            #expect(rows[0].navDate == "2026-11-03")
            #expect(rows[1].navDate == "2026-11-02")
            #expect(rows[2].navDate == nil)
            #expect(rows[2].performance?.currentValue != nil)
        }
    }

    @Test("A matching depository identity across holdings sources stays visible without a duplicated combined contribution")
    func overlappingSources() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([ordinaryFixture(["isin": "SAME-ISIN"])]))
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(["tradingsymbol": "SAME-ISIN", "pledged_quantity": 0]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            #expect(total.totalHoldings == 2)
            #expect(total.currentValue == nil)
            #expect(total.gain == nil)
            #expect(total.valueCount == 0)
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            let rows = try #require(json["rows"] as? [[String: Any]])
            #expect(rows.count == 2)
            #expect(rows.allSatisfy { $0["overlapsSources"] as? Bool == true })
        }
    }

    @Test("A legitimate loss remains negative in both row and combined current-holdings performance")
    func unrealisedLoss() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([ordinaryFixture(["last_price": 50])]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let row = try #require(securities.content.decode(SecuritiesHoldings.self, using: JSONDecoder()).holdings.first)
            #expect(row.performance?.investedCost == 1000)
            #expect(row.performance?.currentValue == 500)
            #expect(row.performance?.gain == -500)
            #expect(row.performance?.returnPercent == -50)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let response = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            let total = try response.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            #expect(total.gain == -500)
            #expect(total.returnPercent == -50)
        }
    }
}
