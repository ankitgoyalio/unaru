//
//  DurableSessionTests.swift
//  unaru
//
//  Created by Ankit Goyal on 04/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

extension KiteLoginTests {
    @Test("Authenticated profile reads cannot silently present another saved account")
    func durableProfileAccountMismatch() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await durableApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            await transport.setProfileResponse(status: 200, body: #"{"status":"success","data":{"user_id":"OTHER","user_name":"Another Account","user_shortname":"Other","user_type":"individual","email":"other@example.invalid","broker":"ZERODHA","exchanges":[],"products":[],"order_types":[],"avatar_url":null,"meta":{"demat_consent":"physical"}}}"#)
            let response = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(response.status == .unauthorized)
            #expect(!response.body.string.contains("Another"))
        }
        await transport.setProfileResponse(status: 200)
        try await durableApp(storage, transport: transport) { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    @Test("Late exchange and profile completions cannot overwrite newer durable authorization", arguments: ["callback", "loginProfile", "profile", "rejectedProfile"])
    func durableOldLogin(operation: String) async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await durableApp(storage, transport: transport) { app in
            let path: String
            if operation == "profile" || operation == "rejectedProfile" {
                _ = try await LogoutTests().signIn(app)
                path = "profile"
                if operation == "rejectedProfile" {
                    await transport.setProfileStatus(403)
                }
            } else {
                let attempt = try await start(app)
                let state = try callbackState(attempt)
                let callback = "kite/callback?state=\(state)&status=success&request_token=test-request"
                if operation == "loginProfile" {
                    _ = try await app.testing().sendRequest(.GET, callback)
                    path = "login/\(attempt.id)"
                } else {
                    path = callback
                }
            }
            await transport.hold(operation == "callback" ? "/session/token" : "/user/profile")
            let pending = Task { try await app.testing().sendRequest(.GET, path, headers: authorization) }
            await transport.waitForHeldRequest()
            let result = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(result.status == .ok)
            let staleSave = try await app.testing().sendRequest(.POST, "session/save", headers: authorization)
            #expect(staleSave.status == .unauthorized)
            await transport.setProfileStatus(200)
            await transport.setAccessToken("new-test-access")
            _ = try await LogoutTests().signIn(app)
            if operation == "rejectedProfile" {
                await transport.setProfileStatus(403)
            }
            await transport.release()
            let obsolete = try await pending.value
            #expect(!obsolete.body.string.contains("Asha"))
        }
        await transport.setProfileStatus(200)
        try await durableApp(storage, transport: transport) { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedIn)
            #expect(await transport.requests.last?.headers["Authorization"] == "token test-key:new-test-access")
        }
    }

    @Test("Invalid authorization stays hidden when secure deletion fails")
    func durableInvalidationDeleteFailure() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await durableApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            storage.fail("delete")
            await transport.setProfileResponse(status: 403, errorType: "TokenException")
            let failed = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            let retry = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(retry.status == .serviceUnavailable)
            #expect(!retry.body.string.contains("signedIn"))
            storage.fail(nil)
            let cleared = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try cleared.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    @Test("Transient restore and storage read failures preserve authorization for retry", arguments: ["load", "network", "gateway", "rateLimit", "permission", "malformed"])
    func durableRestoreRetry(failure: String) async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await seed(storage, transport: transport)
        switch failure {
        case "load": storage.fail("load")
        case "network": await transport.setProfileResponse(status: 200, disconnect: true)
        case "gateway": await transport.setProfileResponse(status: 502)
        case "rateLimit": await transport.setProfileResponse(status: 429)
        case "permission": await transport.setProfileResponse(status: 403, errorType: "PermissionException")
        default: await transport.setProfileResponse(status: 200, body: "invalid")
        }
        try await durableApp(storage, transport: transport) { app in
            let failed = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            #expect(!failed.body.string.contains("Asha"))
            storage.fail(nil)
            await transport.setProfileResponse(status: 200)
            let retry = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try retry.content.decode(SessionStatus.self).state == .signedIn)
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("Confirmed invalidation removes durable authorization", arguments: [401, 403])
    func durableInvalidation(code: Int) async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await seed(storage, transport: transport)
        await transport.setProfileResponse(status: code, errorType: "TokenException")
        try await durableApp(storage, transport: transport) { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedOut)
        }
        await transport.setProfileResponse(status: 200)
        try await durableApp(storage, transport: transport) { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    @Test("Logout deletion failures cannot report success and retry prevents resurrection")
    func durableLogoutRetry() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await durableApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            storage.fail("delete")
            let failed = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            let hidden = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(hidden.status == .serviceUnavailable)
            storage.fail(nil)
            let retry = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(retry.status == .ok)
        }
        try await durableApp(storage, transport: transport) { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    @Test("Saved authorization never crosses API keys or silently changes account")
    func durableIsolation() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await seed(storage, transport: transport)
        try await durableApp(storage, transport: transport, apiKey: "another-test-key") { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedOut)
        }
        await transport.setProfileResponse(status: 200, body: #"{"status":"success","data":{"user_id":"OTHER","user_name":"Another Account","user_shortname":"Other","user_type":"individual","email":"other@example.invalid","broker":"ZERODHA","exchanges":[],"products":[],"order_types":[],"avatar_url":null,"meta":{"demat_consent":"physical"}}}"#)
        try await durableApp(storage, transport: transport) { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedOut)
            #expect(!response.body.string.contains("Another"))
        }
    }

    @Test("Delayed restore cannot resurrect logout or overwrite a newer login", arguments: [true, false])
    func durableRestoreRace(logout: Bool) async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await seed(storage, transport: transport)
        await transport.hold("/user/profile")
        try await durableApp(storage, transport: transport) { app in
            let pending = Task { try await app.testing().sendRequest(.GET, "session", headers: authorization) }
            await transport.waitForHeldRequest()
            if logout {
                let result = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
                #expect(result.status == .ok)
            } else {
                await transport.setAccessToken("new-test-access")
                _ = try await LogoutTests().signIn(app)
            }
            await transport.release()
            let obsolete = try await pending.value
            #expect(obsolete.status == .serviceUnavailable)
            let current = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try current.content.decode(SessionStatus.self).state == (logout ? .signedOut : .signedIn))
        }
        try await durableApp(storage, transport: transport) { app in
            let current = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try current.content.decode(SessionStatus.self).state == (logout ? .signedOut : .signedIn))
            if !logout {
                #expect(await transport.requests.last?.headers["Authorization"] == "token test-key:new-test-access")
            }
        }
    }

    private func seed(_ storage: IsolatedSessionStore, transport: KiteResponses) async throws {
        try await durableApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
        }
    }

    private func durableApp(_ storage: IsolatedSessionStore, transport: KiteResponses, apiKey: String = "test-key", test: (Application) async throws -> Void) async throws {
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: apiKey, apiSecret: "test-secret", transport: transport, store: storage))
        }, test)
    }

    @Test("Cancellation after validation cannot resurrect the cancelled login on restart")
    func durableCancellation() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport, store: storage))
        }) { app in
            let attempt = try await LogoutTests().signIn(app)
            let cancelled = try await app.testing().sendRequest(.DELETE, "login/\(attempt.id)", headers: authorization)
            #expect(cancelled.status == .noContent)
        }
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport, store: storage))
        }) { app in
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    @Test("Failed secure saving keeps identity usable and can retry without another exchange")
    func durableSaveRetry() async throws {
        let storage = IsolatedSessionStore()
        storage.fail("save")
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport, store: storage))
        }) { app in
            _ = try await LogoutTests().signIn(app)
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).persistence == .saveFailed)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(profile.status == .ok)
            storage.fail(nil)
            let retry = try await app.testing().sendRequest(.POST, "session/save", headers: authorization)
            #expect(try retry.content.decode(SessionStatus.self).persistence == .saved)
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("A new helper validates saved authorization without exchanging again")
    func durableRestart() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport, store: storage))
        }) { app in
            _ = try await LogoutTests().signIn(app)
        }
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport, store: storage))
        }) { app in
            let response = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try response.content.decode(SessionStatus.self).state == .signedIn)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(try profile.content.decode(AccountProfile.self).userID == "AB1234")
            #expect(!response.body.string.contains("test-access"))
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }
}

/// Isolated storage at the approved persistence boundary; never reads Keychain.
final class IsolatedSessionStore: KiteSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: String?
    func fail(_ operation: String?) {
        lock.withLock { failure = operation }
    }

    private func check(_ operation: String) throws {
        if failure == operation {
            throw CocoaError(.fileReadNoPermission)
        }
    }

    private var records: [String: SavedKiteSession] = [:]
    func load(apiKey: String) throws -> SavedKiteSession? {
        try lock.withLock { try check("load"); return records[apiKey] }
    }

    func save(_ session: SavedKiteSession, apiKey: String) throws {
        try lock.withLock { try check("save"); records[apiKey] = session }
    }

    func delete(apiKey: String) throws {
        try lock.withLock { try check("delete"); records[apiKey] = nil }
    }
}
