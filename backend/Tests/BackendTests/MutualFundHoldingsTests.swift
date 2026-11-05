//
//  MutualFundHoldingsTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

@Suite("Mutual fund holdings over authenticated HTTP")
struct MutualFundHoldingsTests {
    let authorization = KiteLoginTests().authorization

    @Test("A validated investor can read a successful empty mutual fund source")
    func emptySource() async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            #expect(response.status == .ok)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any]
            #expect((json?["holdings"] as? [Any])?.isEmpty == true)
            #expect(json?["retrievedAt"] != nil)
            #expect(response.headers["Cache-Control"] == ["no-store"])
            #expect(await transport.requests.last?.url.path == "/mf/holdings")
        }
    }

    @Test("Fractional source rows preserve identity, dates, unusable fields and overlap without trusting provider P&L")
    func inspectableRows() async throws {
        let transport = KiteResponses()
        var absentDate = mutualFundHoldingFixture(["tradingsymbol": "ABSENT-DATE"])
        absentDate.removeValue(forKey: "last_price_date")
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(),
            mutualFundHoldingFixture(["last_price_date": "2026-11-02", "quantity": -1, "average_price": 0, "last_price": -2]),
            mutualFundHoldingFixture(["tradingsymbol": "NULL-DATE", "last_price_date": NSNull(), "folio": NSNull(), "pledged_quantity": NSNull()]),
            mutualFundHoldingFixture(["tradingsymbol": "EMPTY-DATE", "last_price_date": "", "folio": ""]),
            absentDate,
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            #expect(response.status == .ok)
            let source = try response.content.decode(MutualFundHoldings.self, using: JSONDecoder())
            #expect(source.holdings.count == 5)
            #expect(Set(source.holdings.map(\.id)).count == 5)
            let row = source.holdings[0]
            #expect(row.fund == "Sample Growth Fund")
            #expect(row.symbol == "TEST-FUND")
            #expect(row.folio == "FOLIO-1")
            #expect(row.quantity == Decimal(string: "12.345678901")!)
            #expect(row.averagePrice == Decimal(string: "42.123456789")!)
            #expect(row.lastPrice == Decimal(string: "43.987654321")!)
            #expect(row.pledgedQuantity == Decimal(string: "2.125")!)
            #expect(row.navDate == "2026-11-03")
            #expect(source.holdings[1].navDate == "2026-11-02")
            #expect(source.holdings[1].quantity == -1)
            #expect(source.holdings[1].averagePrice == 0)
            #expect(source.holdings[1].lastPrice == -2)
            #expect(source.holdings[2].folio == nil)
            #expect(source.holdings[2].pledgedQuantity == nil)
            #expect(source.holdings.dropFirst(2).allSatisfy { $0.navDate == nil })
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            let rows = try #require(json["holdings"] as? [[String: Any]])
            #expect((rows[0]["limitations"] as? [String])?.contains("overlappingRecords") == true)
            #expect((rows[0]["limitations"] as? [String])?.contains("pledgeRelationshipUnknown") == true)
            for limitation in ["quantityUnusable", "acquisitionPriceUnavailable", "navUnavailable"] {
                #expect((rows[1]["limitations"] as? [String])?.contains(limitation) == true)
            }
            #expect((rows[2]["limitations"] as? [String])?.contains("navDateUnavailable") == true)
            for secret in ["pnl", "999999", "api_key", "access_token", "test-access", "test-secret", "test-connection-token", "private-value"] {
                #expect(!response.body.string.contains(secret))
            }
            let upstream = try #require(await transport.requests.last)
            #expect(upstream.url.path == "/mf/holdings")
            #expect(upstream.method == .get)
            #expect(upstream.headers["Authorization"] == "token test-key:test-access")
        }
    }
}

/// Independent fractional-unit example, including deliberately unrelated provider P&L.
func mutualFundHoldingFixture(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var row: [String: Any] = [
        "fund": "Sample Growth Fund", "tradingsymbol": "TEST-FUND", "folio": "FOLIO-1",
        "quantity": NSDecimalNumber(string: "12.345678901"),
        "average_price": NSDecimalNumber(string: "42.123456789"),
        "last_price": NSDecimalNumber(string: "43.987654321"), "last_price_date": "2026-11-03",
        "pledged_quantity": NSDecimalNumber(string: "2.125"), "pnl": 999_999,
        "api_key": "private-value", "access_token": "private-value",
    ]
    row.merge(overrides) { _, new in new }
    return row
}
