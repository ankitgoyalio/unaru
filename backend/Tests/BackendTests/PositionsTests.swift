//
//  PositionsTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import Shared
import Testing
import VaporTesting

@Suite("Net positions over authenticated HTTP")
struct PositionsTests {
    let authorization = KiteLoginTests().authorization

    @Test("Only net rows are exposed, preserving short derivatives, closed activity and delivery purchases")
    func netSource() async throws {
        let transport = KiteResponses()
        let short = positionFixture()
        let closed = positionFixture(["tradingsymbol": "CLOSED", "quantity": 0, "realised": 42, "unrealised": 0])
        let purchase = positionFixture(["tradingsymbol": "DELIVERY", "exchange": "NSE", "product": "CNC", "quantity": 5, "multiplier": 1])
        try await transport.setPositions(body: positionsPayload(net: [short, closed, purchase], day: [short, closed, purchase, positionFixture(["tradingsymbol": "DAY-ONLY"])]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/positions", headers: authorization)
            #expect(response.status == .ok)
            let source = try response.content.decode(NetPositions.self, using: JSONDecoder())
            let first = try #require(source.positions.first)
            #expect(first.averagePrice == Decimal(string: "161.05123456789")!)
            #expect(first.lastPrice == Decimal(string: "160.125")!)
            #expect(first.realised == -25)
            #expect(first.unrealised == 1875)
            #expect(first.pnl == 1850)
            #expect(first.m2m == 1800)
            #expect(first.value == -322_100)
            #expect(first.overnightQuantity == -1)
            #expect(first.buyQuantity == 1)
            #expect(first.sellQuantity == 3)
            #expect(first.dayBuyQuantity == 1)
            #expect(first.daySellQuantity == 2)
            #expect(first.buyM2M == 159_900)
            #expect(first.sellM2M == 482_900)
            #expect(first.dayBuyValue == 160_000)
            #expect(first.daySellValue == 322_000)
            #expect(source.positions[0].state == .current)
            #expect(source.positions[1].state == .closed)
            #expect(Set(source.positions.map(\.id)).count == 3)
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            let rows = try #require(json["positions"] as? [[String: Any]])
            #expect(rows.count == 3)
            #expect(rows[0]["quantity"] as? Int == -2)
            #expect(rows[0]["multiplier"] as? Int == 1000)
            #expect(rows[0]["product"] as? String == "NRML")
            #expect(rows[0]["exchange"] as? String == "MCX")
            #expect(rows[1]["quantity"] as? Int == 0)
            #expect(rows[2]["symbol"] as? String == "DELIVERY")
            #expect(rows[2]["quantity"] as? Int == 5)
            #expect(json["retrievedAt"] != nil)
            #expect(json["valuationDate"] == nil)
            #expect(response.headers["Cache-Control"] == ["no-store"])
            for secret in ["api_key", "access_token", "private-value", "test-access", "test-secret", "DAY-ONLY"] {
                #expect(!response.body.string.contains(secret))
            }
            let holdings = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(try holdings.content.decode(SecuritiesHoldings.self, using: JSONDecoder()).holdings.isEmpty)
        }
    }

    @Test("Empty net data is successful even when the overlapping day collection contains activity")
    func emptyNet() async throws {
        let transport = KiteResponses()
        try await transport.setPositions(body: positionsPayload(net: [], day: [positionFixture()]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/positions", headers: authorization)
            #expect(response.status == .ok)
            #expect(try response.content.decode(NetPositions.self, using: JSONDecoder()).positions.isEmpty)
        }
    }

    @Test("Holdings reads do not supersede a held positions read or merge its delivery sale")
    func independentSources() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([holdingFixture()]))
        try await transport.setPositions(body: positionsPayload(net: [positionFixture(["tradingsymbol": "STOCK", "product": "CNC", "quantity": -40])]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            await transport.hold("/portfolio/positions")
            let pending = Task { try await app.testing().sendRequest(.GET, "portfolio/positions", headers: authorization) }
            await transport.waitForHeldRequest()
            let holdings = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(try holdings.content.decode(SecuritiesHoldings.self, using: JSONDecoder()).holdings[0].quantity == 60)
            await transport.release()
            let positions = try await pending.value
            #expect(positions.status == .ok)
            #expect(try positions.content.decode(NetPositions.self, using: JSONDecoder()).positions[0].quantity == -40)
        }
    }
}

/// Signed commodity contract with a non-unit multiplier and independently specified broker P&L.
func positionFixture(_ overrides: [String: Any] = [:]) -> [String: Any] {
    var row: [String: Any] = [
        "tradingsymbol": "SHORTFUT", "exchange": "MCX", "instrument_token": 53_496_327,
        "product": "NRML", "quantity": -2, "overnight_quantity": -1, "multiplier": 1000,
        "average_price": NSDecimalNumber(string: "161.05123456789"), "last_price": NSDecimalNumber(string: "160.125"),
        "close_price": 162, "value": -322_100, "pnl": 1850, "m2m": 1800, "realised": -25, "unrealised": 1875,
        "buy_quantity": 1, "buy_price": 160, "buy_value": 160_000, "buy_m2m": 159_900,
        "sell_quantity": 3, "sell_price": 161, "sell_value": 483_000, "sell_m2m": 482_900,
        "day_buy_quantity": 1, "day_buy_price": 160, "day_buy_value": 160_000,
        "day_sell_quantity": 2, "day_sell_price": 161, "day_sell_value": 322_000,
        "api_key": "private-value", "access_token": "private-value",
    ]
    row.merge(overrides) { _, new in new }
    return row
}

func positionsPayload(net: [[String: Any]], day: [[String: Any]] = []) throws -> String {
    try String(decoding: JSONSerialization.data(withJSONObject: ["status": "success", "data": ["net": net, "day": day]]), as: UTF8.self)
}
