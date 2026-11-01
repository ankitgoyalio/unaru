//
//  OpenSessionUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testOpenAppRequestsLoginWhenProviderRejectsSession() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(revalidationInterval: "2")
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            backend.respond(path: "/profile", status: 401, body: "{\"code\":\"kiteSignInRequired\"}")
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            XCTAssertFalse(app.buttons["Retry"].exists)
            XCTAssertEqual(backend.loginAttempts, 1)
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testOpenAppRequestsLoginAfterBackendLosesSession() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(revalidationInterval: "2")
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            backend.loseSession()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            let requests = backend.requests
            assertNoRequests(backend, after: requests)
            app.buttons["Sign in with Kite"].click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertEqual(backend.loginAttempts, 2)
        }

        func testOpenAppRetriesTransientFailuresWithoutAnotherLogin() throws {
            for (path, status) in [("/session", 0), ("/profile", 503)] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(revalidationInterval: "2")
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
                backend.respond(path: path, status: status)
                XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 20))
                XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                assertNoRequests(backend, after: backend.requests)
                backend.respond(path: path, status: 200)
                app.buttons["Retry"].click()
                XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
                // Retry also restores monitoring, rather than leaving another stale footer.
                backend.loseSession()
                XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                XCTAssertEqual(backend.loginAttempts, 1)
                XCTAssertEqual(backend.browserHandoffs, 1)
            }
        }

        func testChangingConnectionRejectsDelayedBackgroundValidation() throws {
            let previous = try ControlledBackend()
            let current = try ControlledBackend()
            defer { previous.stop(); current.stop() }
            let app = launch(revalidationInterval: "2")
            defer { cleanUp(app) }
            beginLogin(app, backend: previous)
            previous.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            previous.respond(path: "/profile", status: 200, hold: true,
                             body: "{\"name\":\"Obsolete Person\",\"userID\":\"OLD123\"}")
            waitForPending(previous)
            // A slow check preserves the footer and cannot spawn overlapping checks.
            XCTAssertTrue(app.staticTexts["Asha Rao"].exists)
            assertNoRequests(previous, after: previous.requests)
            app.typeKey(",", modifierFlags: .command)
            save(app, address: current.address, token: "ui-test-token")
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            previous.releaseResponses()
            let obsolete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { app.staticTexts["Obsolete Person"].exists }
            }, object: nil)
            obsolete.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [obsolete], timeout: 3), .completed)
            XCTAssertTrue(app.buttons["Sign in with Kite"].exists)
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            assertNoRequests(previous, after: previous.requests)
        }

        private func assertNoRequests(_ backend: ControlledBackend, after count: Int) {
            let extra = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.requests > count }, object: nil)
            extra.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [extra], timeout: 3), .completed)
        }
    }
#endif
