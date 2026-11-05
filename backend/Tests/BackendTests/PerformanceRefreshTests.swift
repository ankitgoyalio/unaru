//
//  PerformanceRefreshTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import Shared
import Testing
import VaporTesting

extension PerformanceTests {
    @Test("Combined performance requires app and Kite authority and both exact successful reads")
    func protectedPerformance() async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            let rejected = try await app.testing().sendRequest(.POST, "portfolio/performance")
            #expect(rejected.status == .unauthorized)
            let absent = try await requestPerformance(app, securities: "{}", funds: "{}")
            #expect(absent.status == .unauthorized)
            #expect(try absent.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
            _ = try await LogoutTests().signIn(app)
            let missingSources = try await requestPerformance(app, securities: "{}", funds: "{}")
            #expect(missingSources.status == .serviceUnavailable)
        }
    }

    @Test("A failed or in-flight holdings refresh withholds totals until that source recovers; supporting failures are independent")
    func refreshWithholding() async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([ordinaryFixture()]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let initial = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let total = try await requestPerformance(app, securities: initial.body.string, funds: funds.body.string)
            #expect(total.status == .ok)
            await transport.hold("/portfolio/holdings")
            let pending = Task { try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization) }
            await transport.waitForHeldRequest()
            let loading = try await requestPerformance(app, securities: initial.body.string, funds: funds.body.string)
            #expect(loading.status == .serviceUnavailable)
            await transport.setHoldings(status: 503)
            await transport.release()
            #expect(try await pending.value.status == .serviceUnavailable)
            let failed = try await requestPerformance(app, securities: initial.body.string, funds: funds.body.string)
            #expect(failed.status == .serviceUnavailable)
            try await transport.setHoldings(body: holdingsPayload([ordinaryFixture(["last_price": 130])]))
            let fresh = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let superseded = try await requestPerformance(app, securities: initial.body.string, funds: funds.body.string)
            #expect(superseded.status == .serviceUnavailable)
            let recovered = try await requestPerformance(app, securities: fresh.body.string, funds: funds.body.string)
            #expect(try recovered.content.decode(PortfolioPerformance.self, using: JSONDecoder()).currentValue == 1300)
            await transport.setPositions(status: 503)
            await transport.setFunds(status: 503, body: "{}")
            _ = try await app.testing().sendRequest(.GET, "portfolio/positions", headers: authorization)
            _ = try await app.testing().sendRequest(.GET, "portfolio/funds", headers: authorization)
            let independent = try await requestPerformance(app, securities: fresh.body.string, funds: funds.body.string)
            #expect(independent.status == .ok)
        }
    }

    @Test("Authority removal clears cached source reads and a new account cannot aggregate an old account's rows")
    func clearPerformanceAuthority() async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            _ = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            let signedOut = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            #expect(signedOut.status == .unauthorized)
            await transport.setAccessToken("new-access")
            _ = try await LogoutTests().signIn(app)
            let old = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            #expect(old.status == .serviceUnavailable)
        }
    }
}
