//
//  unaruUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import XCTest

/// Acceptance tests use only the running Mac UI and a controlled loopback HTTP server.
final class unaruUITests: XCTestCase {
    @MainActor
    func testFirstRunOpensAndReopensNativeSettings() throws {
        #if os(macOS)
            let app = launch()
            defer { cleanUp(app) }
            XCTAssertTrue(app.buttons["Configure Connection"].waitForExistence(timeout: 5))
            app.buttons["Configure Connection"].click()
            XCTAssertTrue(app.textFields["Backend address"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.secureTextFields["Connection token"].exists)
            app.typeKey("w", modifierFlags: .command)
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(app.textFields["Backend address"].waitForExistence(timeout: 5))
        #else
            throw XCTSkip("Connection setup is a macOS feature.")
        #endif
    }

    #if os(macOS)
        @MainActor
        func testAuthorizedConnectionPersistsAcrossLaunches() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(app.textFields["Backend address"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["Backend address"].value as? String, backend.address)
        }

        @MainActor
        func testRejectedTokenReturnsToSettings() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "incorrect-test-token")
            XCTAssertTrue(app.staticTexts["Check Connection Settings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Kite Sign-In Required"].exists)
            app.typeKey("w", modifierFlags: .command)
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
        }

        @MainActor
        func testConnectionFailureCanRetryWithoutRepeatingSetup() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(status: 0) // Close the real socket without a response.
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.staticTexts["Kite Sign-In Required"].exists)
            app.typeKey("w", modifierFlags: .command)
            backend.respond(status: 200)
            app.buttons["Retry"].click()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
        }

        @MainActor
        func testTemporaryServerFailureOffersRetry() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(status: 503)
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 10))
            app.typeKey("w", modifierFlags: .command)
            backend.respond(status: 200)
            app.buttons["Retry"].click()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
        }

        @MainActor
        func testBackendConfigurationFailureDoesNotAskForKiteSignIn() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(status: 503, body: "{\"code\":\"backendNotConfigured\"}")
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Configure Your Backend"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Kite Sign-In Required"].exists)
            app.typeKey("w", modifierFlags: .command)
            backend.respond(status: 200)
            app.buttons["Retry"].click()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
        }

        @MainActor
        func testChangingConnectionDiscardsDelayedResult() throws {
            let previous = try ControlledBackend()
            let current = try ControlledBackend()
            defer { previous.stop(); current.stop() }
            previous.respond(status: 200, hold: true)
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: previous.address, token: "ui-test-token")
            let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in previous.pendingResponses > 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed)
            save(app, address: current.address, token: "incorrect-test-token")
            XCTAssertTrue(app.staticTexts["Check Connection Settings"].waitForExistence(timeout: 10))
            previous.releaseResponses()
            let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in previous.completedResponses > 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 10), .completed)
            XCTAssertTrue(app.staticTexts["Check Connection Settings"].exists)
            XCTAssertFalse(app.staticTexts["Kite Sign-In Required"].exists)
        }

        @MainActor
        func testRedirectDoesNotForwardConnectionCredentials() throws {
            let backend = try ControlledBackend()
            let destination = try ControlledBackend()
            defer { backend.stop(); destination.stop() }
            backend.respond(status: 302, location: destination.address + "/session")
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 10))
            XCTAssertEqual(destination.requests, 0)
        }

        @MainActor
        func testRemoteHTTPIsRejectedBeforeCredentialsAreSent() {
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: "http://example.invalid", token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Check Connection Settings"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Use HTTPS for a remote backend, or HTTP with a loopback address on this Mac."].firstMatch.exists)
        }

        @MainActor
        func testSetupRemainsAvailableWithSidebarHiddenInBothAppearances() {
            for appearance in ["Light", "Dark"] {
                let app = launch(appearance: appearance)
                defer { cleanUp(app) }
                let toggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
                XCTAssertTrue(toggle.waitForExistence(timeout: 5))
                let splitter = app.splitters.firstMatch
                XCTAssertTrue(splitter.waitForExistence(timeout: 5))
                let previousPosition = splitter.frame.minX
                let start = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 40, dy: 0)))
                XCTAssertGreaterThan(splitter.frame.minX, previousPosition + 10)
                toggle.click()
                XCTAssertTrue(app.buttons["Configure Connection"].isHittable)
                app.typeKey(",", modifierFlags: .command)
                XCTAssertTrue(app.textFields["Backend address"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.secureTextFields["Connection token"].isHittable)
                app.typeKey("w", modifierFlags: .command)
                toggle.click()
                XCTAssertTrue(app.buttons["Configure Connection"].isHittable)
                app.terminate()
            }
        }

        @MainActor
        private func launch(appearance: String = "Light") -> XCUIApplication {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["UNARU_TEST_STORAGE"] = UUID().uuidString
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", appearance]
            app.launch()
            return app
        }

        @MainActor
        private func cleanUp(_ app: XCUIApplication) {
            app.terminate()
            app.launchEnvironment["UNARU_TEST_RESET"] = "1"
            app.launch()
            app.terminate()
        }

        @MainActor
        private func save(_ app: XCUIApplication, address: String, token: String) {
            let field = app.textFields["Backend address"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.click()
            field.typeKey("a", modifierFlags: .command)
            field.typeText(address)
            let credential = app.secureTextFields["Connection token"]
            credential.click()
            credential.typeKey("a", modifierFlags: .command)
            credential.typeText(token)
            app.buttons["Save Connection"].click()
        }
    #endif
}
