//
//  KiteLoginTests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

@Suite("Kite browser login over HTTP")
struct KiteLoginTests {
    let authorization: HTTPHeaders = ["Authorization": "Bearer test-connection-token"]

    @Test("Authorized browser handoff exchanges once and returns only public identity")
    func completion() async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            #expect(attempt.browserURL.host == "kite.zerodha.com")
            #expect(!attempt.browserURL.absoluteString.contains(attempt.id))
            #expect(!attempt.browserURL.absoluteString.contains("test-secret"))
            #expect(!attempt.browserURL.absoluteString.contains("test-connection-token"))
            try await app.testing().test(.GET, "login/\(attempt.id)", headers: authorization, afterResponse: { response async in
                #expect((try? response.content.decode(LoginStatus.self))?.state == .pending)
            })
            try await app.testing().test(.GET, "kite/callback?state=unrelated&status=success&request_token=test-request", afterResponse: { response async in
                #expect(response.status == .badRequest)
            })
            #expect(await transport.requests.isEmpty)
            try await app.testing().test(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request", afterResponse: { response async in
                #expect(response.status == .ok)
                #expect(response.headers["Referrer-Policy"] == ["no-referrer"])
                #expect(!response.body.string.contains("test-request"))
            })
            try await app.testing().test(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request", afterResponse: { response async in
                #expect(response.status == .badRequest)
            })
            try await app.testing().test(.GET, "login/\(attempt.id)", headers: authorization, afterResponse: { response async in
                let status = try? response.content.decode(LoginStatus.self)
                #expect(status?.state == .signedIn)
                #expect(status?.profile == AccountProfile(name: "Asha Rao", userID: "AB1234", email: "asha@example.invalid", broker: "ZERODHA", accountType: "individual", exchanges: ["NSE"], products: ["CNC"], orderTypes: ["LIMIT"]))
                #expect(!response.body.string.contains("test-access"))
                #expect(!response.body.string.contains("test-secret"))
            })
            try await app.testing().test(.GET, "profile", headers: authorization, afterResponse: { response async in
                let profile = try? response.content.decode(AccountProfile.self)
                #expect(profile == AccountProfile(name: "Asha Rao", userID: "AB1234", email: "asha@example.invalid", broker: "ZERODHA", accountType: "individual", exchanges: ["NSE"], products: ["CNC"], orderTypes: ["LIMIT"]))
                let object = try? JSONSerialization.jsonObject(with: Data(response.body.string.utf8)) as? [String: Any]
                #expect(Set(object?.keys.map(\.self) ?? []) == ["name", "userID", "email", "broker", "accountType", "exchanges", "products", "orderTypes"])
            })
            let requests = await transport.requests
            #expect(requests.map(\.url.path) == ["/session/token", "/user/profile", "/user/profile"])
            #expect(requests[0].method == .post)
            #expect(String(decoding: requests[0].body!, as: UTF8.self) == "api_key=test-key&request_token=test-request&checksum=9386bf8374907eda01b4e8acffde5c0bbf3646a9d7532ce10d4c8628c43f744a")
            #expect(requests[1].headers["Authorization"] == "token test-key:test-access")
        }
    }

    @Test("Ambiguous callbacks cannot exchange a request token")
    func ambiguousCallback() async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            try await app.testing().test(.GET, "kite/callback?state=\(state)&state=attacker&status=success&request_token=test-request", afterResponse: { response async in
                #expect(response.status == .badRequest)
            })
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("Denied or incomplete callbacks consume authority and leave login retryable", arguments: [
        "status=cancelled&request_token=test-request", "status=success", "request_token=test-request",
    ])
    func denied(query: String) async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            let response = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&\(query)")
            #expect(response.status == .badRequest)
            let replay = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            #expect(replay.status == .badRequest)
            let status = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try status.content.decode(LoginStatus.self).state == .failed)
            #expect(await transport.requests.isEmpty)
            let next = try await start(app)
            #expect(next.id != attempt.id)
        }
    }

    @Test("Cancelled and replaced attempts cannot authenticate", arguments: [true, false])
    func obsolete(cancel: Bool) async throws {
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            if cancel {
                let response = try await app.testing().sendRequest(.DELETE, "login/\(attempt.id)", headers: authorization)
                #expect(response.status == .noContent)
            } else {
                _ = try await start(app)
            }
            let response = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            #expect(response.status == .badRequest)
            let status = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try status.content.decode(LoginStatus.self).state == .failed)
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("Attempt expiry rejects callback and reports expiry without waiting for wall time")
    func expiry() async throws {
        let clock = LoginClock()
        let transport = KiteResponses()
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport, now: { clock.date }))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            clock.advance()
            let response = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            #expect(response.status == .badRequest)
            let status = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try status.content.decode(LoginStatus.self).state == .expired)
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test("Exchange failures never publish an identity and permit a new attempt", arguments: [403, 502])
    func exchangeFailure(code: Int) async throws {
        let transport = KiteResponses()
        await transport.setExchangeStatus(code)
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            let response = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            #expect(response.status == .badRequest)
            let status = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try status.content.decode(LoginStatus.self).state == .failed)
            let profile = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(profile.status == .unauthorized)
            #expect(await transport.requests.count == 1)
            _ = try await start(app)
        }
    }

    @Test("Temporary profile failure retries the read without exchanging again")
    func profileRetry() async throws {
        let transport = KiteResponses()
        await transport.setProfileStatus(502)
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            let failed = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(failed.status == .serviceUnavailable)
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try session.content.decode(SessionStatus.self).state == .signedOut)
            await transport.setProfileStatus(200)
            let result = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try result.content.decode(LoginStatus.self).state == .signedIn)
            #expect(await transport.requests.filter { $0.url.path == "/session/token" }.count == 1)
            await transport.setProfileStatus(502)
            let temporary = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(temporary.status == .serviceUnavailable)
            await transport.setProfileStatus(200)
            let recovered = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(recovered.status == .ok)
            await transport.setProfileStatus(403)
            let expired = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            #expect(expired.status == .unauthorized)
            #expect(try expired.content.decode(ConnectionProblem.self).code == .kiteSignInRequired)
            let signedOut = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try signedOut.content.decode(SessionStatus.self).state == .signedOut)
            let oldLogin = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try oldLogin.content.decode(LoginStatus.self).state == .failed)
        }
    }

    @Test("A provider token rejection during initial profile retrieval never signs in")
    func profileRejected() async throws {
        let transport = KiteResponses()
        await transport.setProfileStatus(403)
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            let status = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            #expect(try status.content.decode(LoginStatus.self).state == .failed)
            #expect(try status.content.decode(LoginStatus.self).profile == nil)
        }
    }

    @Test("In-flight exchange and profile results cannot revive an obsolete attempt", arguments: ["/session/token", "/user/profile"], ["cancel", "replace", "expire"])
    func inFlight(path: String, action: String) async throws {
        let clock = LoginClock()
        let transport = KiteResponses()
        await transport.hold(path)
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport, now: { clock.date }))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            if path == "/user/profile" {
                _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            }
            let pending = Task {
                try await app.testing().sendRequest(.GET, path == "/session/token"
                    ? "kite/callback?state=\(state)&status=success&request_token=test-request"
                    : "login/\(attempt.id)", headers: authorization)
            }
            await transport.waitForHeldRequest()
            switch action {
            case "cancel": _ = try await app.testing().sendRequest(.DELETE, "login/\(attempt.id)", headers: authorization)
            case "replace": _ = try await start(app)
            default: clock.advance()
            }
            await transport.release()
            let old = try await pending.value
            #expect(!old.body.string.contains("Asha Rao"))
            let session = try await app.testing().sendRequest(.GET, "session", headers: authorization)
            #expect(try session.content.decode(SessionStatus.self).state == .signedOut)
        }
    }

    func start(_ app: Application) async throws -> LoginAttempt {
        let response = try await app.testing().sendRequest(.POST, "login", headers: authorization)
        #expect(response.status == .ok)
        return try response.content.decode(LoginAttempt.self, using: JSONDecoder())
    }

    func callbackState(_ attempt: LoginAttempt) throws -> String {
        let url = try #require(URLComponents(url: attempt.browserURL, resolvingAgainstBaseURL: false))
        let redirect = try #require(url.queryItems?.first { $0.name == "redirect_params" }?.value)
        return try #require(URLComponents(string: "https://example.invalid/?" + redirect)?.queryItems?.first { $0.name == "state" }?.value)
    }
}

/// A controllable wall clock at the expiry boundary.
private final class LoginClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var date: Date {
        lock.withLock { value }
    }

    func advance() {
        lock.withLock { value = value.addingTimeInterval(301) }
    }
}
