//
//  AccountProfileTests.swift
//  unaru
//
//  Created by Ankit Goyal on 02/11/2026.

@testable import Backend
import Foundation
import Shared
import Testing
import VaporTesting

extension KiteLoginTests {
    @Test("Public profile preserves provider codes and empty permissions while rejecting unsafe avatars", arguments: [
        "https://images.example.invalid/avatar.png",
        "http://images.example.invalid/avatar.png",
        "https://user:secret@images.example.invalid/avatar.png",
        "https://images.example.invalid/avatar.png?token=secret",
        "https://images.example.invalid/avatar.png#secret",
    ])
    func publicProfile(avatar: String) async throws {
        let transport = KiteResponses()
        let data: [String: Any] = [
            "user_id": "AB1234", "user_name": "Asha Rao", "user_shortname": "Asha",
            "user_type": "individual", "email": "", "broker": "ZERODHA",
            "exchanges": [], "products": ["FUTURE-PRODUCT"], "order_types": ["SL-M"],
            "avatar_url": avatar, "meta": ["demat_consent": "physical"],
            "api_key": "private-key", "access_token": "private-access",
            "public_token": "private-public", "refresh_token": "private-refresh",
        ]
        let body = try String(decoding: JSONSerialization.data(withJSONObject: ["status": "success", "data": data]), as: UTF8.self)
        await transport.setProfileResponse(status: 200, body: body)
        try await withApp(configure: { app in
            try routes(app, connectionToken: "test-connection-token", login: KiteLogin(apiKey: "test-key", apiSecret: "test-secret", transport: transport))
        }) { app in
            let attempt = try await start(app)
            let state = try callbackState(attempt)
            _ = try await app.testing().sendRequest(.GET, "kite/callback?state=\(state)&status=success&request_token=test-request")
            let completion = try await app.testing().sendRequest(.GET, "login/\(attempt.id)", headers: authorization)
            let completedProfile = try completion.content.decode(LoginStatus.self).profile
            let response = try await app.testing().sendRequest(.GET, "profile", headers: authorization)
            let profile = try response.content.decode(AccountProfile.self)
            #expect(profile == completedProfile)
            #expect(profile.exchanges == [])
            #expect(profile.products == ["FUTURE-PRODUCT"])
            #expect(profile.orderTypes == ["SL-M"])
            #expect(profile.email == "")
            #expect(profile.avatarURL?.absoluteString == (avatar == "https://images.example.invalid/avatar.png" ? avatar : nil))
            for response in [completion, response] {
                #expect(!response.body.string.contains("private-"))
                #expect(!response.body.string.contains("demat"))
                #expect(!response.body.string.contains("shortname"))
            }
        }
    }
}
