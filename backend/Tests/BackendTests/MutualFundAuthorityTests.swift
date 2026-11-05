//
//  MutualFundAuthorityTests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

@testable import Backend
import Foundation
import KiteConnect
import Shared
import Testing
import VaporTesting

extension MutualFundHoldingsTests {
    @Test("Refreshing one holdings source does not supersede the other", arguments: [true, false])
    func independentSources(holdMutualFunds: Bool) async throws {
        let transport = KiteResponses()
        try await sessionApp(IsolatedSessionStore(), transport: transport) { app in
            _ = try await LogoutTests().signIn(app)
            await transport.hold(holdMutualFunds ? "/mf/holdings" : "/portfolio/holdings")
            let path = holdMutualFunds ? "portfolio/mutual-funds" : "portfolio/holdings"
            let other = holdMutualFunds ? "portfolio/holdings" : "portfolio/mutual-funds"
            let pending = Task { try await app.testing().sendRequest(.GET, path, headers: authorization) }
            await transport.waitForHeldRequest()
            let refreshed = try await app.testing().sendRequest(.GET, other, headers: authorization)
            #expect(refreshed.status == .ok)
            await transport.release()
            #expect(try await pending.value.status == .ok)
        }
    }
}
