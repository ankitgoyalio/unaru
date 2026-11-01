//
//  BackendTests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

@testable import Backend
import Testing
import VaporTesting

@Suite("App Tests")
struct BackendTests {
    @Test("Test Hello World Route")
    func helloWorld() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == "Hello, world!")
            })
        }
    }

    @Test("Session status rejects missing app authorization")
    func missingAuthorization() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "session", afterResponse: { res async in
                #expect(res.status == .unauthorized)
                #expect(!res.body.string.contains("signedOut"))
            })
        }
    }

    @Test("Authorized connection reports that Kite sign-in is required")
    func authorizedSessionStatus() async throws {
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token")
        }) { app in
            try await app.testing().test(.GET, "session", headers: ["Authorization": "Bearer test-connection-token"], afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == "{\"state\":\"signedOut\"}")
                #expect(res.headers["Cache-Control"] == ["no-store"])
            })
        }
    }

    @Test("Protected status rejects incorrect or URL-based credentials", arguments: [
        ("Bearer incorrect-token", "session"),
        ("Basic test-connection-token", "session"),
        ("", "session?token=test-connection-token"),
        ("Bearer test-connection-tokem", "session"),
    ])
    func rejectedAuthorization(authorization: String, path: String) async throws {
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token")
        }) { app in
            try await app.testing().test(.GET, path, headers: ["Authorization": authorization], afterResponse: { res async in
                #expect(res.status == .unauthorized)
                #expect(!res.body.string.contains("signedOut"))
                #expect(!res.body.string.contains("test-connection-token"))
            })
        }
    }

    @Test("Missing server configuration is distinct from Kite sign-in", arguments: [nil, "", "bad token"] as [String?])
    func backendNotConfigured(token: String?) async throws {
        try await withApp(configure: { app in
            try routes(app, connectionToken: token)
        }) { app in
            try await app.testing().test(.GET, "session", headers: ["Authorization": "Bearer test-connection-token"], afterResponse: { res async in
                #expect(res.status == .serviceUnavailable)
                #expect(res.body.string == "{\"code\":\"backendNotConfigured\"}")
                #expect(res.headers["Cache-Control"] == ["no-store"])
            })
        }
    }
}
