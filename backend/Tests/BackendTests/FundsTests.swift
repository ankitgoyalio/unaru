//
//  FundsTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

@Suite("Trading funds over authenticated HTTP")
struct FundsTests {
    let authorization = KiteLoginTests().authorization

    @Test("Segment availability and utilisation preserve broker values without component addition")
    func balances() async throws {
        let transport = KiteResponses()
        try await transport.setFunds(body: fundsPayload())
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/funds", headers: authorization)
            #expect(response.status == .ok)
            let source = try response.content.decode(TradingFunds.self, using: JSONDecoder())
            let json = try #require(JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any])
            let segments = try #require(json["segments"] as? [[String: Any]])
            #expect(segments.count == 2)
            #expect(segments[0]["segment"] as? String == "equity")
            #expect(segments[0]["enabled"] as? Bool == true)
            #expect(source.segments[0].available == Decimal(string: "1234.56789"))
            #expect(source.segments[0].utilised == -25)
            #expect(segments[1]["available"] as? Int == 0)
            let components = try #require(segments[0]["availableComponents"] as? [String: Any])
            #expect(components["cash"] as? Int == 9000)
            #expect(components["collateral"] as? Int == 3000)
            #expect(json["retrievedAt"] != nil)
            #expect(response.headers["Cache-Control"] == ["no-store"])
            for secret in ["api_key", "access_token", "private-value", "test-access", "test-connection-token"] {
                #expect(!response.body.string.contains(secret))
            }
            let upstream = try #require(await transport.requests.last)
            #expect(upstream.url.path == "/user/margins")
            #expect(upstream.method == .get)
            #expect(upstream.headers["Authorization"] == "token test-key:test-access")
        }
    }

    @Test("Holdings and funds refreshes do not supersede one another")
    func independentSources() async throws {
        let transport = KiteResponses()
        try await transport.setFunds(body: fundsPayload())
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            await transport.hold("/user/margins")
            let pending = Task { try await app.testing().sendRequest(.GET, "portfolio/funds", headers: authorization) }
            await transport.waitForHeldRequest()
            let holdings = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(holdings.status == .ok)
            await transport.release()
            let funds = try await pending.value
            #expect(funds.status == .ok)
            #expect(try funds.content.decode(TradingFunds.self, using: JSONDecoder()).segments.count == 2)
        }
    }

    @Test("Disabled segments remain explicit and are distinct from a failed read")
    func disabledSegments() async throws {
        let transport = KiteResponses()
        try await transport.setFunds(body: fundsPayload(enabled: false))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let response = try await app.testing().sendRequest(.GET, "portfolio/funds", headers: authorization)
            #expect(response.status == .ok)
            let source = try response.content.decode(TradingFunds.self, using: JSONDecoder())
            #expect(source.segments.count == 2)
            #expect(source.segments.allSatisfy { !$0.enabled })
            #expect(source.segments[0].availableComponents == [.cash: 9000, .openingBalance: 8000,
                                                               .liveBalance: 7000, .intradayPayin: 1000, .adhocMargin: 2000, .collateral: 3000])
            #expect(source.segments[0].utilisedComponents == [.debits: -25, .span: 100, .exposure: 20,
                                                              .m2mUnrealised: -30, .m2mRealised: 5, .optionPremium: 10, .holdingSales: 200,
                                                              .liquidCollateral: 2, .delivery: 3, .stockCollateral: 4, .turnover: 0, .payout: 50])
        }
    }
}

func fundsPayload(enabled: Bool = true) throws -> String {
    func segment(_ net: NSDecimalNumber, enabled: Bool) -> [String: Any] {
        ["enabled": enabled, "net": net,
         "available": ["cash": 9000, "opening_balance": 8000, "live_balance": 7000,
                       "intraday_payin": 1000, "adhoc_margin": 2000, "collateral": 3000],
         "utilised": ["debits": -25, "span": 100, "exposure": 20, "m2m_unrealised": -30,
                      "m2m_realised": 5, "option_premium": 10, "holding_sales": 200,
                      "liquid_collateral": 2, "delivery": 3, "stock_collateral": 4,
                      "turnover": 0, "payout": 50], "api_key": "private-value"]
    }
    return try String(decoding: JSONSerialization.data(withJSONObject: ["status": "success", "data": [
        "equity": segment(NSDecimalNumber(string: "1234.56789"), enabled: enabled),
        "commodity": segment(0, enabled: enabled),
    ]]), as: UTF8.self)
}
