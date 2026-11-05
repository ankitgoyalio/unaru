//
//  CancellationRecoveryTests.swift
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
    @Test("Failed cancellation hides validated authority and retries after helper restart")
    func cancellationRemovalRecovery() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        var cancelledID = ""
        try await sessionApp(storage, transport: transport) { app in
            let attempt = try await start(app)
            cancelledID = attempt.id
            let state = try callbackState(attempt)
            _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            // One status read is delayed while another completes validation and saving.
            // The app cancels before accepting the signedIn response.
            await transport.hold("/user/profile")
            let delayed = Task { try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization) }
            await transport.waitForHeldRequest()
            let validated = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try validated.content.decode(LoginStatus.self).state == .signedIn)
            storage.fail("delete")
            let cancel = try await app.testing().sendRequest(.DELETE, "login/\(attempt.id)", headers: authorization)
            #expect(cancel.status == .serviceUnavailable)
            let old = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try old.content.decode(LoginStatus.self).state == .failed)
            #expect(!old.body.string.contains("Asha"))
            let save = try await app.testing().sendRequest(.POST, "session/save", headers: authorization)
            #expect(save.status == .unauthorized)
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(session.status == .serviceUnavailable)
            await transport.release()
            let obsolete = try await delayed.value
            #expect(try obsolete.content.decode(LoginStatus.self).state == .failed)
            #expect(!obsolete.body.string.contains("Asha"))
        }
        try await sessionApp(storage, transport: transport) { app in
            // The app's credential-free intent is replayed before any restore request.
            let retry = try await app.testing().sendRequest(.DELETE, "login/\(cancelledID)", headers: authorization)
            #expect(retry.status == .serviceUnavailable)
            let hidden = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(hidden.status == .serviceUnavailable)
            storage.fail(nil)
            let removed = try await app.testing().sendRequest(.DELETE, "login/\(cancelledID)", headers: authorization)
            #expect(removed.status == .noContent)
        }
        try await sessionApp(storage, transport: transport) { app in
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedOut)
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("Cancellation while validation is pending rejects delayed status and callbacks")
    func pendingCancellation() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await sessionApp(storage, transport: transport) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            let pending = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try pending.content.decode(LoginStatus.self).state == .pending)
            let callback = "kite/callback?state=\(state)&status=success&request_token=test-request"
            _ = try await app.testing().sendRequest(.GET, callback)
            await transport.hold("/user/profile")
            let delayed = Task { try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization) }
            await transport.waitForHeldRequest()
            let cancel = try await app.testing().sendRequest(.DELETE, "login/\(attempt.id)", headers: authorization)
            #expect(cancel.status == .noContent)
            await transport.release()
            let old = try await delayed.value
            #expect(try old.content.decode(LoginStatus.self).state == .failed)
            #expect(try await app.testing().sendRequest(.GET, callback).status == .badRequest)
        }
        try await sessionApp(storage, transport: transport) { app in
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    @Test("Stale cancellation cannot remove a newer saved session before or after restart")
    func staleCancellation() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        var cancelledID = ""
        try await sessionApp(storage, transport: transport) { app in
            cancelledID = try await LogoutTests().signIn(app).id
            storage.fail("delete")
            #expect(try await app.testing().sendRequest(.DELETE, "login/\(cancelledID)", headers: authorization).status == .serviceUnavailable)
            storage.fail(nil)
            // Starting newer authority finishes the old removal first.
            await transport.setAccessToken("new-test-access")
            _ = try await LogoutTests().signIn(app)
            let stale = try await app.testing().sendRequest(.DELETE, "login/\(cancelledID)", headers: authorization)
            #expect(stale.status == .noContent)
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedIn)
        }
        try await sessionApp(storage, transport: transport) { app in
            let stale = try await app.testing().sendRequest(.DELETE, "login/\(cancelledID)", headers: authorization)
            #expect(stale.status == .noContent)
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedIn)
            #expect(await transport.requests.last?.headers["Authorization"] == "token test-key:new-test-access")
        }
    }
}
