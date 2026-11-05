//
//  HoldingsTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

@Suite("Securities holdings over authenticated HTTP")
struct HoldingsTests {
    let authorization = KiteLoginTests().authorization

    @Test("A validated investor can read a successful empty holdings source")
    func emptySource() async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(response.status == .ok)
            let json = try JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any]
            #expect((json?["holdings"] as? [Any])?.isEmpty == true)
            #expect(json?["retrievedAt"] != nil)
            #expect(response.headers["Cache-Control"] == ["no-store"])
        }
    }

    @Test("Real SDK rows retain ordinary, T1, MTF and collateral fields without exposing arbitrary provider data")
    func inspectableRows() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([
            holdingFixture(),
            holdingFixture(["tradingsymbol": "ETF", "isin": "ETF-ISIN", "average_price": 0, "last_price": -1]),
            holdingFixture(["tradingsymbol": "BOND", "isin": "BOND-ISIN", "quantity": -2, "discrepancy": true]),
            holdingFixture(["exchange": "BSE"]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(response.status == .ok)
            let source = try response.content.decode(SecuritiesHoldings.self, using: JSONDecoder())
            #expect(source.holdings.count == 4)
            #expect(source.valuationDate == nil)
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            let rows = try #require(json["holdings"] as? [[String: Any]])
            let first = rows[0]
            #expect(first["exchange"] as? String == "NSE")
            #expect(first["isin"] as? String == "TEST-ISIN")
            #expect(first["product"] as? String == "CNC")
            #expect(first["quantity"] as? Int == 60)
            #expect(first["t1Quantity"] as? Int == 5)
            #expect(first["usedQuantity"] as? Int == 40)
            #expect(first["collateralQuantity"] as? Int == 7)
            #expect(first["realisedQuantity"] as? Int == 60)
            #expect(first["openingQuantity"] as? Int == 100)
            #expect(first["authorisedQuantity"] as? Int == 60)
            #expect(first["shortQuantity"] as? Int == 2)
            #expect(first["collateralType"] as? String == "pledge")
            let mtf = first["mtf"] as? [String: Any]
            #expect(mtf?["quantity"] as? Int == 10)
            #expect(mtf?["usedQuantity"] as? Int == 3)
            #expect(mtf?["value"] as? Int == 1250)
            #expect(mtf?["initialMargin"] as? Int == 300)
            #expect(first["investmentType"] as? String == "unknown")
            #expect(first["name"] == nil)
            #expect((first["limitations"] as? [String])?.contains("overlappingRecords") == true)
            #expect((first["limitations"] as? [String])?.contains("collateralRelationshipUnknown") == true)
            #expect((rows[1]["limitations"] as? [String])?.contains("acquisitionPriceUnavailable") == true)
            #expect((rows[1]["limitations"] as? [String])?.contains("marketPriceUnavailable") == true)
            #expect((rows[2]["limitations"] as? [String])?.contains("quantityUnusable") == true)
            #expect(Set(source.holdings.map(\.id)).count == 4)
            #expect(source.holdings[0].averagePrice == Decimal(string: "100.123456789")!)
            #expect(source.holdings[0].lastPrice == Decimal(string: "125.125")!)
            for secret in ["api_key", "access_token", "test-access", "test-secret", "test-connection-token", "private-value", "authorisation"] {
                #expect(!response.body.string.contains(secret))
            }
            let upstream = try #require(await transport.requests.last)
            #expect(upstream.url.path == "/portfolio/holdings")
            #expect(upstream.method == .get)
            #expect(upstream.headers["Authorization"] == "token test-key:test-access")
        }
    }
}

/// A documented same-day sale (100 settled, 40 sold), with separate T1 and financing data.
/// Provider references: https://kite.trade/forum/discussion/comment/52974/ and /comment/50543/.
func holdingFixture(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var row: [String: Any] = [
        "tradingsymbol": "STOCK", "exchange": "NSE", "instrument_token": 123,
        "isin": "TEST-ISIN", "product": "CNC", "quantity": 60, "t1_quantity": 5,
        "realised_quantity": 60, "authorised_quantity": 60, "opening_quantity": 100,
        "used_quantity": 40, "short_quantity": 2, "collateral_quantity": 7, "collateral_type": "pledge",
        "discrepancy": false, "price": 0, "average_price": NSDecimalNumber(string: "100.123456789"), "last_price": NSDecimalNumber(string: "125.125"),
        "close_price": 120, "pnl": 999_999, "day_change": 5, "day_change_percentage": 4,
        "mtf": ["quantity": 10, "used_quantity": 3, "average_price": 100, "value": 1250, "initial_margin": 300],
        "api_key": "private-value", "access_token": "private-value", "authorisation": ["private": "private-value"],
    ]
    row.merge(overrides) { _, new in new }
    return row
}

func holdingsPayload(_ rows: [[String: Any]]) throws -> String {
    try String(decoding: JSONSerialization.data(withJSONObject: ["status": "success", "data": rows]), as: UTF8.self)
}
