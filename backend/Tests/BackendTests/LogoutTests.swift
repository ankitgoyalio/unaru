//
//  LogoutTests.swift
//  unaru
//
//  Created by Ankit Goyal on 03/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

@Suite("Unconditional Kite logout over HTTP")
struct LogoutTests {
    let authorization: HTTPHeaders = ["Authorization": "Bearer test-connection-token"]

    @Test("Logout requires authorization and revokes only the current token")
    func confirmed() async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await signIn(app)
            let denied = try await app.testing().sendRequest(.POST, "logout")
            #expect(denied.status == .unauthorized)
            let before = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try before.content.decode(SessionStatus.self).state == .signedIn)
            let result = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(result.status == .ok)
            #expect(result.body.string == #"{"revocation":"confirmed"}"#)
            try await expectSignedOut(app, attempt: attempt)
            let requests = await transport.requests.filter { $0.method == .delete }
            #expect(requests.count == 1)
            #expect(requests.first?.url.path == "/session/token")
            #expect(requests.first?.headers["Authorization"] == "token test-key:test-access")
            let query = requests.first.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems }
            #expect(query?.first { $0.name == "access_token" }?.value == "test-access")
            #expect(query?.first { $0.name == "api_key" }?.value == "test-key")
        }
    }

    @Test("Only a positive provider result confirms revocation", arguments: [
        #"{"status":"success","data":false}"#,
        #"{"status":"success","data":{}}"#,
        #"{"status":"error","error_type":"NetworkException","message":"Synthetic failure"}"#,
        "disconnect",
    ])
    func unconfirmed(body: String) async throws {
        let transport = KiteResponses()
        await transport.setInvalidation(body: body, disconnect: body == "disconnect")
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await signIn(app)
            let result = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(result.body.string == #"{"revocation":"unconfirmed"}"#)
            try await expectSignedOut(app, attempt: attempt)
            _ = try await signIn(app)
        }
    }

    @Test("Authority detaches before revocation and old cleanup cannot clear a newer session", arguments: [true, false])
    func heldRevocation(timeout: Bool) async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(
                apiKey: "test-key", apiSecret: "test-secret", transport: transport,
                revocationTimeout: timeout ? .milliseconds(30) : .seconds(5),
            ))
        }) { app in
            let attempt = try await signIn(app)
            await transport.hold("/session/token")
            let pending = Task { try await app.testing().sendRequest(.POST, "logout", headers: authorization) }
            await transport.waitForHeldRequest()
            try await expectSignedOut(app, attempt: attempt)
            let duplicate = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            #expect(duplicate.body.string == #"{"revocation":"unconfirmed"}"#)
            #expect(await transport.requests.filter { $0.method == .delete }.count == 1)
            if timeout {
                // This must return even though the held transport ignores cancellation.
                let result = try await pending.value
                #expect(result.body.string == #"{"revocation":"unconfirmed"}"#)
            }
            await transport.setAccessToken("new-test-access")
            _ = try await signIn(app)
            await transport.release()
            if !timeout {
                let result = try await pending.value
                #expect(result.body.string == #"{"revocation":"confirmed"}"#)
            }
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try session.content.decode(SessionStatus.self).state == .signedIn)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(profile.status == .ok)
            let requests = await transport.requests
            let revoked = try #require(requests.first { $0.method == .delete })
            let query = URLComponents(url: revoked.url, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.first { $0.name == "access_token" }?.value == "test-access")
            #expect(requests.last?.headers["Authorization"] == "token test-key:new-test-access")
        }
    }

    @Test("Logout rejects late callbacks and profile reads", arguments: ["callback", "loginProfile", "profile", "rejectedProfile"])
    func obsoleteReads(operation: String) async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let helpers = KiteLoginTests()
            let attempt: LoginAttempt
            let path: String
            if operation == "profile" || operation == "rejectedProfile" {
                attempt = try await signIn(app)
                path = "profile"
                if operation == "rejectedProfile" {
                    await transport.setProfileStatus(403)
                }
            } else {
                attempt = try await helpers.start(app)
                let state = try helpers.callbackState(attempt)
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
            _ = try await app.testing().sendRequest(.POST, "logout", headers: authorization)
            try await expectSignedOut(app, attempt: attempt)
            // Completing an older request after a new login must neither publish old
            // identity nor remove the newer session, including old TokenException errors.
            await transport.setProfileStatus(200)
            _ = try await signIn(app)
            if operation == "rejectedProfile" {
                await transport.setProfileStatus(403)
            }
            await transport.release()
            let old = try await pending.value
            #expect(!old.body.string.contains("Asha Rao"))
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try session.content.decode(SessionStatus.self).state == .signedIn)
        }
    }

    func signIn(_ app: Application) async throws -> LoginAttempt {
        let helpers = KiteLoginTests()
        let attempt = try await helpers.start(app)
        let state = try helpers.callbackState(attempt)
        _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
        let result = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
        #expect(try result.content.decode(LoginStatus.self).state == .signedIn)
        return attempt
    }

    func expectSignedOut(_ app: Application, attempt: LoginAttempt) async throws {
        let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
        #expect(try session.content.decode(SessionStatus.self).state == .signedOut)
        let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
        #expect(profile.status == .unauthorized)
        let old = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
        #expect(try old.content.decode(LoginStatus.self).state == .failed)
        #expect(!old.body.string.contains("Asha"))
    }
}
