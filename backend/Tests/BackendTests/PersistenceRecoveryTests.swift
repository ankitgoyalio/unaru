//
//  PersistenceRecoveryTests.swift
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
    @Test("An unfinished durable logout blocks a new browser login until deletion recovers")
    func unfinishedLogoutBlocksLogin() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        try await sessionApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            storage.fail("delete")
            let failed = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            let blocked = try await app.testing().sendRequest(.POST, "login", headers: authorization)
            #expect(blocked.status == .serviceUnavailable)
            #expect(!blocked.body.string.contains("browserURL"))
            #expect(!blocked.body.string.contains("backendNotConfigured"))
            storage.fail(nil)
            let retry = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(retry.status == .ok)
        }
        try await sessionApp(storage, transport: transport) { app in
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    @Test("Login immediately reports unsaved usable authority and repeated retry recovers across restart")
    func loginSaveWarningAndRetry() async throws {
        let storage = IsolatedSessionStore()
        let transport = KiteResponses()
        storage.fail("save")
        try await sessionApp(storage, transport: transport) { app in
            let attempt = try await LogoutTests().signIn(app)
            let login = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            let object = try #require(JSONSerialization.jsonObject(with: Data(login.body.string.utf8)) as? [String: Any])
            #expect(object["persistence"] as? String == "saveFailed")
            let retry = try await app.testing().sendRequest(.POST, "session/save", headers: authorization)
            #expect(try retry.content.decode(SessionStatus.self).state == .signedIn)
            #expect(try retry.content.decode(SessionStatus.self).persistence == .saveFailed)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(try profile.content.decode(AccountProfile.self).userID == "AB1234")
            storage.fail(nil)
            let saved = try await app.testing().sendRequest(.POST, "session/save", headers: authorization)
            #expect(try saved.content.decode(SessionStatus.self).persistence == .saved)
            #expect(saved.headers["Cache-Control"] == ["no-store"])
            #expect(!saved.body.string.contains("test-access"))
            #expect(!login.body.string.contains("test-access"))
        }
        try await sessionApp(storage, transport: transport) { app in
            let restored = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try restored.content.decode(SessionStatus.self).state == .signedIn)
            #expect(try restored.content.decode(SessionStatus.self).persistence == .saved)
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
        }
    }

    @Test("A delayed secure save cannot survive logout or overwrite newer authorization", arguments: [true, false])
    func delayedSaveSuperseded(logout: Bool) async throws {
        let storage = PausedSessionStore()
        let transport = KiteResponses()
        try await sessionApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            storage.hold("save")
            let save = Task { try await app.testing().sendRequest(.POST, "session/save", headers: authorization) }
            try await storage.waitUntilPaused()
            let newer = Task {
                if logout {
                    let response = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
                    #expect(response.status == .ok)
                } else {
                    await transport.setAccessToken("new-test-access")
                    _ = try await LogoutTests().signIn(app)
                }
            }
            storage.release()
            _ = try await save.value
            try await newer.value
        }
        try await sessionApp(storage, transport: transport) { app in
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == (logout ? .signedOut : .signedIn))
            if !logout {
                #expect(await transport.requests.last?.headers["Authorization"] == "token test-key:new-test-access")
            }
        }
    }

    @Test("Delayed deletion and provider completion cannot delete or hide a newer durable login")
    func delayedDeletionSuperseded() async throws {
        let storage = PausedSessionStore()
        let transport = KiteResponses()
        try await sessionApp(storage, transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            storage.hold("delete")
            await transport.hold("/session/token")
            let logout = Task { try await app.testing().sendRequest(.POST, "logout", headers: authorization) }
            try await storage.waitUntilPaused()
            storage.release()
            await transport.waitForHeldRequest()
            await transport.setAccessToken("new-test-access")
            _ = try await LogoutTests().signIn(app)
            await transport.release()
            #expect(try await logout.value.status == .ok)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(profile.status == .ok)
        }
        try await sessionApp(storage, transport: transport) { app in
            let status = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try status.content.decode(SessionStatus.self).state == .signedIn)
            #expect(await transport.requests.last?.headers["Authorization"] == "token test-key:new-test-access")
        }
    }
}

/// A synchronous external store can block, but cannot resume after newer actor authority.
private final class PausedSessionStore: KiteSessionStore, @unchecked Sendable {
    private let storage = IsolatedSessionStore()
    private let condition = NSCondition()
    private var operation: String?
    private var paused = false

    func hold(_ operation: String) {
        condition.lock()
        self.operation = operation
        paused = false
        condition.unlock()
    }

    func release() {
        condition.lock()
        operation = nil
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilPaused() async throws {
        for _ in 0 ..< 5000 {
            if isPaused {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        release()
        throw CocoaError(.featureUnsupported)
    }

    private var isPaused: Bool {
        condition.lock()
        defer { condition.unlock() }
        return paused
    }

    private func wait(_ operation: String) {
        condition.lock()
        defer { condition.unlock() }
        guard self.operation == operation else { return }
        paused = true
        condition.broadcast()
        while self.operation == operation {
            condition.wait()
        }
    }

    func load(apiKey: String) throws -> SavedKiteSession? {
        try storage.load(apiKey: apiKey)
    }

    func save(_ session: SavedKiteSession, apiKey: String) throws {
        wait("save")
        try storage.save(session, apiKey: apiKey)
    }

    func delete(apiKey: String) throws {
        wait("delete")
        try storage.delete(apiKey: apiKey)
    }
}
