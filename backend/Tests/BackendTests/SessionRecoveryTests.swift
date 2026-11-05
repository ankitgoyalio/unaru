//
//  SessionRecoveryTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

extension KiteLoginTests {
    @Test("An older restore rejection cannot discard a newer validated saved session")
    func supersededRestoreRejection() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await sessionApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
        }
        try await sessionApp(storage, transport: transport) { app in
            await transport.hold("/user/profile")
            let pending = Task { try await app.testing().sendRequest(.GET, "session", headers: authorization) }
            await transport.waitForHeldRequest()
            let newer = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try newer.content.decode(SessionStatus.self).state == .signedIn)
            await transport.setProfileResponse(status: 403, errorType: "TokenException")
            await transport.release()
            let obsolete = try await pending.value
            #expect(obsolete.status == .serviceUnavailable)
            #expect(!obsolete.body.string.contains("signedIn"))
            let current = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try current.content.decode(SessionStatus.self).state == .signedIn)
        }
        await transport.setProfileResponse(status: 200)
        try await sessionApp(storage, transport: transport) { app in
            let restored = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(try restored.content.decode(AccountProfile.self).userID == "AB1234")
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("Repeated storage access and timeout failures recover in place without a new browser login", arguments: ["storage", "timeout"])
    func repeatedRecovery(failure: String) async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await sessionApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
        }
        if failure == "storage" {
            storage.fail("load")
        } else {
            await transport.setProfileTimeout(true)
        }
        try await sessionApp(storage, transport: transport) { app in
            let count = await transport.requests.count
            for path in ["session", "profile"] {
                let denied = try await app.testing().sendRequest(.GET, path, headers: ["Authorization": "Bearer wrong-launch-token"])
                #expect(denied.status == .unauthorized)
                #expect(!denied.body.string.contains("kiteSignInRequired"))
            }
            #expect(await transport.requests.count == count)
            for _ in 0 ..< 2 {
                let failed = try await app.testing().sendRequest(.GET, "session", headers: authorization)
                #expect(failed.status == .serviceUnavailable)
                #expect(try failed.content.decode(ConnectionProblem.self).code == (failure == "storage" ? .sessionStorageUnavailable : .kiteSessionUnavailable))
                #expect(!failed.body.string.contains("Asha"))
            }
            storage.fail(nil)
            await transport.setProfileTimeout(false)
            let retry = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try retry.content.decode(SessionStatus.self).state == .signedIn)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(try profile.content.decode(AccountProfile.self).name == "Asha Rao")
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }
}
