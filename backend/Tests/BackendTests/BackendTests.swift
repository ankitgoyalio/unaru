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
}
