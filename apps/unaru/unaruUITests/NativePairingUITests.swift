//
//  NativePairingUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import Foundation
    import XCTest

    /// Optional acceptance check against a native backend and the real login Keychain.
    @MainActor
    extension unaruUITests {
        func testNativeLoopbackPairsUsingKeychain() throws {
            guard let address = ProcessInfo.processInfo.environment["UNARU_NATIVE_PAIRING_ADDRESS"] else {
                throw XCTSkip("Set TEST_RUNNER_UNARU_NATIVE_PAIRING_ADDRESS to a running native loopback backend.")
            }
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            connect(app, address: address)
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.staticTexts["Approve This Connection"].exists)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
        }
    }
#endif
