//
//  unaruUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import XCTest

/// Acceptance tests use only the running Mac UI and a controlled loopback HTTP server.
final class unaruUITests: XCTestCase {
    #if os(macOS)
        @MainActor
        func testKiteBrowserCompletionShowsAccountButton() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            app.buttons["Sign in with Kite"].click()
            XCTAssertTrue(app.descendants(matching: .any)["Complete Sign-In in Your Browser"].firstMatch.waitForExistence(timeout: 5))
            let handoff = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.browserHandoffs > 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [handoff], timeout: 5), .completed)
            XCTAssertEqual(backend.browserURL, "https://kite.zerodha.com/connect/login?v=3&api_key=test-key&redirect_params=state%3Dtest-state")
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["AB1234"].exists)
            XCTAssertTrue(app.staticTexts["AR"].exists)
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            XCTAssertFalse(app.buttons["Sign Out"].exists)
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = "Connected Kite account"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        @MainActor
        func testConnectionFailureCanRetryWithoutRepeatingSetup() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(status: 0) // Close the real socket without a response.
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.staticTexts["Kite Sign-In Required"].exists)
            backend.respond(status: 200)
            app.buttons["Retry"].click()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
        }

        @MainActor
        func testTemporaryServerFailureOffersRetry() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(status: 503)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 10))
            backend.respond(status: 200)
            app.buttons["Retry"].click()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
        }

        @MainActor
        func testBackendConfigurationFailureDoesNotAskForKiteSignIn() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(status: 503, body: "{\"code\":\"backendNotConfigured\"}")
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            XCTAssertTrue(app.staticTexts["Set Up Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Kite Sign-In Required"].exists)
            backend.respond(status: 200)
            app.buttons["Retry"].click()
            XCTAssertTrue(app.staticTexts["Kite Sign-In Required"].waitForExistence(timeout: 10))
        }

        @MainActor
        func testRedirectDoesNotForwardConnectionCredentials() throws {
            let backend = try ControlledBackend()
            let destination = try ControlledBackend()
            defer { backend.stop(); destination.stop() }
            backend.respond(status: 302, location: destination.address + "/session")
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 10))
            XCTAssertEqual(destination.requests, 0)
        }

        @MainActor
        func testCancellingLoginRejectsDelayedCompletionAndAllowsNewLogin() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.respond(status: 200, hold: true, body: "{\"state\":\"signedIn\",\"profile\":{\"name\":\"Obsolete Person\",\"userID\":\"OLD123\"}}")
            waitForPending(backend)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 5))
            assertConnectionSheet(app)
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
                let app = launch(backend: backend)
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
            let app = launch(backend: backend)
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
        func testSignInSheetTransitionsToReadableSidebarInBothAppearances() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.useAvatar(backend.address + "/missing-avatar")
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                assertConnectionSheet(app)
                capture(app, name: "Sign-in sheet - \(appearance)")
                app.typeKey(.escape, modifierFlags: [])
                assertConnectionSheet(app)
                XCTAssertTrue(app.buttons["Sign in with Kite"].isHittable)
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(app.buttons["Cancel Sign-In"].waitForExistence(timeout: 5))
                assertConnectionSheet(app)
                capture(app, name: "Browser sign-in pending - \(appearance)")
                waitForHandoff(backend, count: 1)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Cancel Sign-In"].waitForNonExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Hide Sidebar"].exists)
                XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))
                XCTAssertFalse(app.descendants(matching: .any)["Connection sheet"].exists)
                XCTAssertTrue(app.staticTexts["AR"].waitForExistence(timeout: 5))
                let splitter = app.splitters.firstMatch
                let start = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -30, dy: 0)))
                XCTAssertTrue(app.staticTexts["Asha Rao"].isHittable)
                XCTAssertTrue(app.staticTexts["AB1234"].isHittable)
                XCTAssertGreaterThan(app.staticTexts["Asha Rao"].frame.minY, app.windows.firstMatch.frame.midY)
                capture(app, name: "Authenticated sidebar - \(appearance)")
            }
        }

        @MainActor
        func assertConnectionSheet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(app.descendants(matching: .any)["Connection sheet"].firstMatch.exists, file: file, line: line)
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch.exists, file: file, line: line)
            XCTAssertLessThan(sheet.frame.width, app.windows.firstMatch.frame.width, file: file, line: line)
            XCTAssertLessThan(sheet.frame.height, app.windows.firstMatch.frame.height, file: file, line: line)
        }

        @MainActor
        func capture(_ app: XCUIApplication, name: String) {
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        @MainActor
        func beginLogin(_ app: XCUIApplication, backend: ControlledBackend) {
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
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
        func launch(backend: ControlledBackend? = nil, appearance: String = "Light", revalidationInterval: String? = nil, helperPort: String? = nil) -> XCUIApplication {
            continueAfterFailure = false
            let app = XCUIApplication()
            if backend == nil {
                // Reserve a test-only port rather than collide with the owner's running services.
                if let helperPort {
                    app.launchEnvironment["UNARU_TEST_BACKEND_PORT"] = helperPort
                } else {
                    let reservation = try! ControlledBackend()
                    app.launchEnvironment["UNARU_TEST_BACKEND_PORT"] = URL(string: reservation.address)!.port!.description
                    reservation.stop()
                }
            }
            app.launchEnvironment["UNARU_TEST_STORAGE"] = UUID().uuidString
            app.launchEnvironment["UNARU_TEST_BACKEND_ADDRESS"] = backend?.address
            app.launchEnvironment["UNARU_TEST_BROWSER"] = "1"
            app.launchEnvironment["UNARU_TEST_APPEARANCE"] = appearance
            app.launchEnvironment["UNARU_TEST_REVALIDATION_SECONDS"] = revalidationInterval
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
            app.launch()
            return app
        }

        @MainActor
        func cleanUp(_ app: XCUIApplication) {
            app.terminate()
        }

    #endif
}
