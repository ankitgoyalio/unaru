//
//  PerformanceRecoveryTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

extension PerformanceTests {
    @Test("Either holdings source can recover to empty without reusing stale totals or refetching its successful peer", arguments: [true, false])
    func emptySourceRecovery(securitiesFail: Bool) async throws {
        let transport = KiteResponses()
        try await transport.setHoldings(body: holdingsPayload([ordinaryFixture()]))
        try await transport.setMutualFunds(body: holdingsPayload([
            mutualFundHoldingFixture(["quantity": 2.5, "average_price": 40, "last_price": 80, "pledged_quantity": 0, "last_price_date": NSNull()]),
        ]))
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            let securities = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            let funds = try await app.testing().sendRequest(.GET, "portfolio/mutual-funds", headers: authorization)
            let initial = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            #expect(try initial.content.decode(PortfolioPerformance.self, using: JSONDecoder()).currentValue == 1400)
            #expect(try funds.content.decode(MutualFundHoldings.self, using: JSONDecoder()).holdings[0].navDate == nil)
            if securitiesFail {
                await transport.setHoldings(status: 503)
            } else {
                await transport.setMutualFunds(status: 503)
            }
            let path = securitiesFail ? "portfolio/holdings" : "portfolio/mutual-funds"
            let failed = try await app.testing().sendRequest(.GET, path, headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            #expect(try failed.content.decode(ConnectionProblem.self).code == .portfolioUnavailable)
            let withheld = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            #expect(withheld.status == .serviceUnavailable)
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try session.content.decode(SessionStatus.self).state == .signedIn)
            if securitiesFail {
                await transport.setHoldings()
            } else {
                await transport.setMutualFunds()
            }
            let empty = try await app.testing().sendRequest(.GET, path, headers: authorization)
            #expect(empty.status == .ok)
            let recovered = try await requestPerformance(app,
                                                         securities: securitiesFail ? empty.body.string : securities.body.string,
                                                         funds: securitiesFail ? funds.body.string : empty.body.string)
            let total = try recovered.content.decode(PortfolioPerformance.self, using: JSONDecoder())
            #expect(total.currentValue == (securitiesFail ? 200 : 1200))
            #expect(total.totalHoldings == 1)
            let obsolete = try await requestPerformance(app, securities: securities.body.string, funds: funds.body.string)
            #expect(obsolete.status == .serviceUnavailable)
            #expect(await transport.requests.filter { $0.url.path == (securitiesFail ? "/mf/holdings" : "/portfolio/holdings") }.count == 1)
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
            #expect(recovered.headers["Cache-Control"] == ["no-store"])
        }
    }
}
