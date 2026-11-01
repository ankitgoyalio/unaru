//
//  SessionRestorationTests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

extension KiteLoginTests {
    @Test("Restoration validates with Kite and retains the session across transient failures", arguments: ["network", "gateway", "rateLimit", "permission", "malformed"])
    func restorationRetry(failure: String) async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            try await authenticate(app)
            switch failure {
            case "network": await transport.setProfileResponse(status: 200, disconnect: true)
            case "gateway": await transport.setProfileResponse(status: 502)
            case "rateLimit": await transport.setProfileResponse(status: 429)
            case "permission": await transport.setProfileResponse(status: 403, errorType: "PermissionException")
            default: await transport.setProfileResponse(status: 200, body: "invalid-json")
            }
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedIn)
            let failed = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            #expect(!failed.body.string.contains("Asha Rao"))
            await transport.setProfileResponse(status: 200)
            let recovered = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(recovered.status == .ok)
            #expect(try recovered.content.decode(AccountProfile.self) == AccountProfile(name: "Asha Rao", userID: "AB1234"))
            #expect(recovered.headers["Cache-Control"] == ["no-store"])
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("Provider authentication rejection clears session while invalid app credentials cannot validate it", arguments: [401, 403])
    func restorationRejection(code: Int) async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            try await authenticate(app)
            let count = await transport.requests.count
            for header in ["", "Bearer wrong-token"] {
                let denied = try await app.testing().sendRequest(.GET, "profile", headers: ["Authorization": header])
                #expect(denied.status == .unauthorized)
                #expect(!denied.body.string.contains("kiteSignInRequired"))
            }
            #expect(await transport.requests.count == count)
            await transport.setProfileResponse(status: code, errorType: "TokenException")
            let rejected = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(rejected.status == .unauthorized)
            #expect(try rejected.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
            #expect(rejected.headers["Cache-Control"] == ["no-store"])
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedOut)
            await transport.setProfileResponse(status: 200)
            try await authenticate(app)
            let restored = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(try restored.content.decode(AccountProfile.self).userID == "AB1234")
        }
    }

    @Test("A fresh backend has no authenticated session or public identity")
    func restartedBackend() async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            try await authenticate(app)
        }
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedOut)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(profile.status == .unauthorized)
            #expect(try profile.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
        }
    }

    @Test("A delayed validation cannot publish identity after a newer login supersedes the session")
    func supersededValidation() async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            try await authenticate(app)
            await transport.hold("/user/profile")
            let pending = Task { try await app.testing().sendRequest(.GET, "profile", headers: authorization) }
            await transport.waitForHeldRequest()
            try await authenticate(app)
            await transport.release()
            let obsolete = try await pending.value
            #expect(obsolete.status == .serviceUnavailable)
            #expect(!obsolete.body.string.contains("Asha Rao"))
            let current = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(current.status == .ok)
        }
    }

    private func authenticate(_ app: Application) async throws {
        let attempt = try await start(app)
        let state = try callbackState(attempt)
        let callback = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
        #expect(callback.status == .ok)
        let status = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
        #expect(try status.content.decode(LoginStatus.self).state == .signedIn)
    }
}
