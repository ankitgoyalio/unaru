//
//  SourceAuthorityTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

@Suite("Portfolio source authority over authenticated HTTP")
struct SourceAuthorityTests {
    let authorization = KiteLoginTests().authorization

    @Test("Portfolio sources require app authorization and a validated Kite session", arguments: PortfolioSource.allCases)
    func protectedSource(source: PortfolioSource) async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            for token in ["", "Bearer wrong"] {
                let response = try await app.testing().sendRequest(.GET, source.path, headers: ["Authorization": token])
                #expect(response.status == .unauthorized)
                #expect(!response.body.string.contains("kiteSignInRequired"))
            }
            let noSession = try await app.testing().sendRequest(.GET, source.path, headers: authorization)
            #expect(noSession.status == .unauthorized)
            #expect(try noSession.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
            let attempt = try await KiteLoginTests().start(app)
            let state = try KiteLoginTests().callbackState(attempt)
            _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            let unvalidated = try await app.testing().sendRequest(.GET, source.path, headers: authorization)
            #expect(unvalidated.status == .unauthorized)
            #expect(await transport.requests.filter { $0.url.path == source.upstreamPath }.isEmpty)
        }
    }

    @Test("Temporary source failures preserve authorization and retry without another exchange", arguments: PortfolioSource.allCases, SourceFailure.allCases)
    func sourceRecovery(source: PortfolioSource, failure: SourceFailure) async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            switch failure {
            case .network: try await source.respond(transport, failure: .networkConnectionLost)
            case .timeout: try await source.respond(transport, failure: .timedOut)
            case .gateway: try await source.respond(transport, status: 502)
            case .rateLimit: try await source.respond(transport, status: 429)
            case .permission: try await source.respond(transport, status: 403, body: #"{"status":"error","error_type":"PermissionException","message":"private-diagnostic"}"#)
            case .missingField: try await source.respond(transport, body: source.missingFieldPayload)
            case .malformed: try await source.respond(transport, body: "not-json")
            }
            let failed = try await app.testing().sendRequest(.GET, source.path, headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            #expect(try failed.content.decode(ConnectionProblem.self).code == .portfolioUnavailable)
            #expect(!failed.body.string.contains("private-diagnostic"))
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try session.content.decode(SessionStatus.self).state == .signedIn)
            if source != .securities {
                let holdings = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
                #expect(holdings.status == .ok)
            }
            try await source.respond(transport)
            let recovered = try await app.testing().sendRequest(.GET, source.path, headers: authorization)
            #expect(recovered.status == .ok)
            switch source {
            case .securities: #expect(try recovered.content.decode(SecuritiesHoldings.self, using: JSONDecoder()).holdings.isEmpty)
            case .mutualFunds: #expect(try recovered.content.decode(MutualFundHoldings.self, using: JSONDecoder()).holdings.isEmpty)
            case .positions: #expect(try recovered.content.decode(NetPositions.self, using: JSONDecoder()).positions.isEmpty)
            case .funds: #expect(try recovered.content.decode(TradingFunds.self, using: JSONDecoder()).segments.count == 2)
            }
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("Only confirmed source token rejection removes authority", arguments: PortfolioSource.allCases, [401, 403])
    func sourceInvalidation(source: PortfolioSource, status: Int) async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            let attempt = try await LogoutTests().signIn(app)
            try await source.respond(transport, status: status, body: #"{"status":"error","error_type":"TokenException","message":"private-diagnostic"}"#)
            let rejected = try await app.testing().sendRequest(.GET, source.path, headers: authorization)
            #expect(rejected.status == .unauthorized)
            #expect(try rejected.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
            try await LogoutTests().expectSignedOut(app, attempt: attempt)
        }
    }

    @Test("Obsolete source success and rejection cannot disclose data or remove newer authority", arguments: PortfolioSource.allCases, ObsoleteSourceScenario.all)
    func obsoleteSource(source: PortfolioSource, scenario: ObsoleteSourceScenario) async throws {
        let status = scenario.status
        let action = scenario.action
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            try await source.respond(transport)
            await transport.hold(source.upstreamPath)
            let pending = Task { try await app.testing().sendRequest(.GET, source.path, headers: authorization) }
            await transport.waitForHeldRequest()
            switch action {
            case .logout, .newLogin:
                _ = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
                if action == .newLogin {
                    await transport.setAccessToken("new-access")
                    _ = try await LogoutTests().signIn(app)
                }
            case .refresh:
                let latest = try await app.testing().sendRequest(.GET, source.path, headers: authorization)
                #expect(latest.status == .ok)
            case .expiry:
                await transport.setProfileStatus(403)
                let expired = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
                #expect(expired.status == .unauthorized)
                await transport.setProfileStatus(200)
            }
            let body = status == 200 ? try source.populatedPayload : #"{"status":"error","error_type":"TokenException","message":"old-rejection"}"#
            try await source.respond(transport, status: status, body: body)
            await transport.release()
            let obsolete = try await pending.value
            #expect(obsolete.status == .serviceUnavailable)
            #expect(!obsolete.body.string.contains(source.privateMarker))
            #expect(!obsolete.body.string.contains("old-rejection"))
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            let expected: SessionStatus.State = action == .newLogin || action == .refresh ? .signedIn : .signedOut
            #expect(try session.content.decode(SessionStatus.self).state == expected)
        }
    }
}
