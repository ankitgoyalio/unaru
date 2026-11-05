//
//  HoldingsAuthorityTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

extension HoldingsTests {
    @Test("Holdings require app authorization and a validated Kite session")
    func protectedSource() async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            for token in ["", "Bearer wrong"] {
                let response = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: ["Authorization": token])
                #expect(response.status == .unauthorized)
                #expect(!response.body.string.contains("kiteSignInRequired"))
            }
            let noSession = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(noSession.status == .unauthorized)
            #expect(try noSession.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
            let attempt = try await KiteLoginTests().start(app)
            let state = try KiteLoginTests().callbackState(attempt)
            _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            let unvalidated = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(unvalidated.status == .unauthorized)
            #expect(await transport.requests.filter { $0.url.path == "/portfolio/holdings" }.isEmpty)
        }
    }

    @Test("Temporary holdings failures preserve authorization and retry without another exchange", arguments: ["network", "timeout", "gateway", "rateLimit", "permission", "malformed", "missingField"])
    func sourceRecovery(failure: String) async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            switch failure {
            case "network": await transport.setHoldings(failure: .networkConnectionLost)
            case "timeout": await transport.setHoldings(failure: .timedOut)
            case "gateway": await transport.setHoldings(status: 502)
            case "rateLimit": await transport.setHoldings(status: 429)
            case "permission": await transport.setHoldings(status: 403, body: #"{"status":"error","error_type":"PermissionException","message":"private-diagnostic"}"#)
            case "missingField": await transport.setHoldings(body: #"{"status":"success","data":[{"tradingsymbol":"UNKNOWN"}]}"#)
            default: await transport.setHoldings(body: "not-json")
            }
            let failed = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            #expect(try failed.content.decode(ConnectionProblem.self).code == .portfolioUnavailable)
            #expect(!failed.body.string.contains("private-diagnostic"))
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try session.content.decode(SessionStatus.self).state == .signedIn)
            await transport.setHoldings()
            let recovered = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(recovered.status == .ok)
            #expect(try recovered.content.decode(SecuritiesHoldings.self, using: JSONDecoder()).holdings.isEmpty)
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("Only confirmed holdings token rejection removes authority", arguments: [401, 403])
    func sourceInvalidation(status: Int) async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            let attempt = try await LogoutTests().signIn(app)
            await transport.setHoldings(status: status, body: #"{"status":"error","error_type":"TokenException","message":"private-diagnostic"}"#)
            let rejected = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
            #expect(rejected.status == .unauthorized)
            #expect(try rejected.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
            try await LogoutTests().expectSignedOut(app, attempt: attempt)
        }
    }

    @Test("Obsolete holdings success and rejection cannot disclose data or remove newer authority", arguments: [200, 403], ["logout", "newLogin", "refresh", "expiry"])
    func obsoleteSource(status: Int, action: String) async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            await transport.hold("/portfolio/holdings")
            let pending = Task { try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization) }
            await transport.waitForHeldRequest()
            switch action {
            case "logout", "newLogin":
                _ = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
                if action == "newLogin" {
                    await transport.setAccessToken("new-access")
                    _ = try await LogoutTests().signIn(app)
                }
            case "refresh":
                let latest = try await app.testing().sendRequest(.GET, "portfolio/holdings", headers: authorization)
                #expect(latest.status == .ok)
            default:
                await transport.setProfileStatus(403)
                let expired = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
                #expect(expired.status == .unauthorized)
                await transport.setProfileStatus(200)
            }
            let body = status == 200 ? try holdingsPayload([holdingFixture()]) : #"{"status":"error","error_type":"TokenException","message":"old-rejection"}"#
            await transport.setHoldings(status: status, body: body)
            await transport.release()
            let obsolete = try await pending.value
            #expect(obsolete.status == .serviceUnavailable)
            #expect(!obsolete.body.string.contains("STOCK"))
            #expect(!obsolete.body.string.contains("old-rejection"))
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            let expected: SessionStatus.State = action == "newLogin" || action == "refresh" ? .signedIn : .signedOut
            #expect(try session.content.decode(SessionStatus.self).state == expected)
        }
    }
}
