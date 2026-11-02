//
//  SharedTests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation
import Shared
import Testing

@Test func olderProfileRemainsDecodable() throws {
    let profile = try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"name":"Asha Rao","userID":"AB1234"}"#.utf8))
    #expect(profile.email == nil)
    #expect(profile.broker == nil)
    #expect(profile.accountType == nil)
    #expect(profile.exchanges == nil)
    #expect(profile.products == nil)
    #expect(profile.orderTypes == nil)
}

@Test func profilePreservesExplicitEmptyPermissions() throws {
    let profile = try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"name":"Asha Rao","userID":"AB1234","email":"asha@example.invalid","broker":"ZERODHA","accountType":"individual","exchanges":[],"products":["CNC"],"orderTypes":["LIMIT"]}"#.utf8))
    #expect(profile.email == "asha@example.invalid")
    #expect(profile.broker == "ZERODHA")
    #expect(profile.accountType == "individual")
    #expect(profile.exchanges == [])
    #expect(profile.products == ["CNC"])
    #expect(profile.orderTypes == ["LIMIT"])
    #expect(try JSONDecoder().decode(AccountProfile.self, from: JSONEncoder().encode(profile)) == profile)
}
