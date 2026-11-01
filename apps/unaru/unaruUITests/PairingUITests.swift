//
//  PairingUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import XCTest

    /// Exercises approval through the running app rather than exposing generated credentials.
    @MainActor
    extension unaruUITests {
        func testConnectionWaitsForOwnerApprovalWithoutTokenEntry() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.requireApproval()
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            connect(app, address: backend.address)
            XCTAssertTrue(app.staticTexts["Approve This Connection"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Backend pair 12345678"].firstMatch.exists)
            XCTAssertFalse(app.secureTextFields["Connection token"].exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            backend.approvePairing()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Approve This Connection"].exists)
        }

        func testCancelledPairingCannotRestoreConnection() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.requireApproval()
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            connect(app, address: backend.address)
            XCTAssertTrue(app.staticTexts["Approve This Connection"].firstMatch.waitForExistence(timeout: 10))
            app.windows.containing(.textField, identifier: "Backend address").firstMatch.buttons["Cancel Connection"].click()
            let revoked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.wasPairingCancelled }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [revoked], timeout: 5), .completed)
            backend.approvePairing()
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(app.buttons["Configure Connection"].exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
        }
    }
#endif
