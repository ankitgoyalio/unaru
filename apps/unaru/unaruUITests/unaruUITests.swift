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
        func testKiteBrowserCompletionShowsNoninteractiveIdentity() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            app.typeKey("w", modifierFlags: .command)
            app.buttons["Sign in with Kite"].click()
            XCTAssertTrue(app.descendants(matching: .any)["Complete Sign-In in Your Browser"].firstMatch.waitForExistence(timeout: 5))
            let handoff = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.browserHandoffs > 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [handoff], timeout: 5), .completed)
            XCTAssertEqual(backend.browserURL, "https://kite.zerodha.com/connect/login?v=3&api_key=test-key&redirect_params=state%3Dtest-state")
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["AB1234"].exists)
            XCTAssertTrue(app.staticTexts["AR"].exists)
            XCTAssertFalse(app.buttons["Asha Rao"].exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            XCTAssertFalse(app.buttons["Sign Out"].exists)
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = "Connected Kite account"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        @MainActor
        func testAuthorizedConnectionPersistsAcrossLaunches() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Sign in with Kite"].exists)
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
                let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                screenshot.name = "Connection setup - \(appearance)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
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
        func testCancellingLoginRejectsDelayedCompletionAndAllowsNewLogin() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.respond(status: 200, hold: true, body: "{\"state\":\"signedIn\",\"profile\":{\"name\":\"Obsolete Person\",\"userID\":\"OLD123\"}}")
            waitForPending(backend)
            app.buttons["Cancel Sign-In"].click()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 5))
            backend.respond(status: 200)
            backend.releaseResponses()
            XCTAssertFalse(app.staticTexts["Obsolete Person"].exists)
            app.buttons["Sign in with Kite"].click()
            XCTAssertTrue(app.buttons["Cancel Sign-In"].waitForExistence(timeout: 5))
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Obsolete Person"].exists)
        }

        @MainActor
        func testLoginDenialAndExpiryAllowAnotherAttempt() throws {
            for outcome in ["failed", "expired"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch()
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.finishLogin(state: outcome)
                XCTAssertTrue(app.staticTexts["Sign-In Not Completed"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["Sign in with Kite"].isHittable)
                XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
                app.buttons["Sign in with Kite"].click()
                XCTAssertTrue(app.buttons["Cancel Sign-In"].waitForExistence(timeout: 5))
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            }
        }

        @MainActor
        func testTemporaryLoginFailureRetriesCompletionWithoutAnotherBrowserHandoff() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.respond(status: 503)
            XCTAssertTrue(app.buttons["Retry Sign-In"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            backend.respond(status: 200)
            backend.completeLogin()
            app.buttons["Retry Sign-In"].click()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        @MainActor
        func testChangingConnectionRejectsDelayedLoginIdentity() throws {
            let previous = try ControlledBackend()
            let current = try ControlledBackend()
            defer { previous.stop(); current.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: previous)
            previous.respond(status: 200, hold: true, body: "{\"state\":\"signedIn\",\"profile\":{\"name\":\"Obsolete Person\",\"userID\":\"OLD123\"}}")
            waitForPending(previous)
            app.typeKey(",", modifierFlags: .command)
            save(app, address: current.address, token: "ui-test-token")
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            previous.releaseResponses()
            XCTAssertFalse(app.staticTexts["Obsolete Person"].exists)
            XCTAssertTrue(app.buttons["Sign in with Kite"].exists)
        }

        @MainActor
        func testSignInWithHiddenSidebarAndReadableFooterInBothAppearances() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.useAvatar(backend.address + "/missing-avatar")
                let app = launch(appearance: appearance)
                defer { cleanUp(app) }
                app.buttons["Configure Connection"].click()
                save(app, address: backend.address, token: "ui-test-token")
                XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                app.typeKey("w", modifierFlags: .command)
                let toggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
                toggle.click()
                XCTAssertTrue(app.buttons["Sign in with Kite"].isHittable)
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(app.buttons["Cancel Sign-In"].waitForExistence(timeout: 5))
                waitForHandoff(backend, count: 1)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Cancel Sign-In"].waitForNonExistence(timeout: 10))
                toggle.click()
                XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["AR"].waitForExistence(timeout: 5))
                let splitter = app.splitters.firstMatch
                let start = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -30, dy: 0)))
                XCTAssertTrue(app.staticTexts["Asha Rao"].isHittable)
                XCTAssertTrue(app.staticTexts["AB1234"].isHittable)
                XCTAssertGreaterThan(app.staticTexts["Asha Rao"].frame.minY, app.windows.firstMatch.frame.midY)
            }
        }

        @MainActor
        func beginLogin(_ app: XCUIApplication, backend: ControlledBackend) {
            app.buttons["Configure Connection"].click()
            save(app, address: backend.address, token: "ui-test-token")
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            app.typeKey("w", modifierFlags: .command)
            app.buttons["Sign in with Kite"].click()
            XCTAssertTrue(app.buttons["Cancel Sign-In"].waitForExistence(timeout: 5))
            let handoff = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.browserHandoffs > 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [handoff], timeout: 5), .completed)
        }

        func waitForHandoff(_ backend: ControlledBackend, count: Int) {
            let handoff = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.browserHandoffs >= count }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [handoff], timeout: 5), .completed)
        }

        func waitForPending(_ backend: ControlledBackend) {
            let pending = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.pendingResponses > 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 5), .completed)
        }

        @MainActor
        func launch(appearance: String = "Light", revalidationInterval: String? = nil) -> XCUIApplication {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["UNARU_TEST_STORAGE"] = UUID().uuidString
            app.launchEnvironment["UNARU_TEST_BROWSER"] = "1"
            app.launchEnvironment["UNARU_TEST_REVALIDATION_SECONDS"] = revalidationInterval
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleInterfaceStyle", appearance]
            app.launch()
            return app
        }

        @MainActor
        func cleanUp(_ app: XCUIApplication) {
            app.terminate()
            app.launchEnvironment["UNARU_TEST_RESET"] = "1"
            app.launch()
            app.terminate()
        }

        @MainActor
        func save(_ app: XCUIApplication, address: String, token: String) {
            pasteConnection(app, address: address, token: token)
        }
    #endif
}
