//
//  BundledBackendUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 02/11/2026.

#if os(macOS)
    import XCTest

    /// Exercises the shipped helper rather than the controlled network fixture.
    @MainActor
    extension unaruUITests {
        func testOccupiedPortDoesNotReceiveCredentialsAndRetryStartsOwnHelper() throws {
            let occupied = try ControlledBackend()
            defer { occupied.stop() }
            let app = launch(helperPort: URL(string: occupied.address)!.port!.description)
            defer { cleanUp(app) }
            XCTAssertTrue(app.staticTexts["Unaru Couldn’t Start"].waitForExistence(timeout: 20))
            XCTAssertEqual(occupied.requests, 0)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            occupied.stop()
            app.buttons["Retry"].click()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 20))
        }

        func testBundledBackendStartsWithoutConnectionSetupAndRelaunches() {
            let app = launch()
            defer { cleanUp(app) }
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.buttons["Configure Connection"].exists)
            XCTAssertFalse(app.buttons["Connect"].exists)
            XCTAssertFalse(app.textFields["Backend address"].exists)
            XCTAssertFalse(app.staticTexts["Approve This Connection"].exists)
            assertConnectionSheet(app)
            capture(app, name: "Automatic bundled startup")
            // Force termination must close the lifetime pipe and release the callback port.
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 20))
            app.buttons["Sign in with Kite"].click()
            XCTAssertTrue(app.staticTexts["Set Up Kite"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Open Configuration Folder"].exists)
            XCTAssertTrue(app.buttons["Retry"].exists)
        }
    }
#endif
