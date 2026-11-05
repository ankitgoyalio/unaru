//
//  SessionTestSupport.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import KiteConnect
import VaporTesting

/// Authorized HTTP fixture with isolated storage and fake provider responses.
func sessionApp(_ storage: any KiteSessionStore, transport: KiteResponses, apiKey: String = "test-key", test: (Application) async throws -> Void) async throws {
    try await withApp(configure: { app in
        try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: apiKey, apiSecret: "test-secret", transport: transport, store: storage))
    }, test)
}
