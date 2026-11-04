//
//  PersistenceRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 04/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testSaveFailureKeepsAccountUsableAndRetryClearsWarning() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.usePersistence("saveFailed")
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Sign-In Not Saved"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Open Kite account"].isEnabled)
            XCTAssertTrue(app.staticTexts["You can keep using your Kite account. If you quit Unaru, you’ll need to sign in again."].exists)
            backend.respond(path: "/session/save", status: 200, body: #"{"state":"signedIn","persistence":"saveFailed"}"#)
            app.buttons["Retry Saving"].click()
            let failed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                backend.requestedPaths.contains("/session/save") && app.buttons["Retry Saving"].isEnabled
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 5), .completed)
            XCTAssertTrue(app.staticTexts["Sign-In Not Saved"].exists)
            app.buttons["Open Kite account"].click()
            XCTAssertTrue(app.sheets.firstMatch.buttons["Log Out"].waitForExistence(timeout: 5))
            app.sheets.firstMatch.buttons["Done"].click()
            backend.usePersistence("saved")
            backend.respond(path: "/session/save", status: 200, body: #"{"state":"signedIn","persistence":"saved"}"#)
            app.buttons["Retry Saving"].click()
            XCTAssertTrue(app.staticTexts["Sign-In Not Saved"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Sign-In Not Saved"].exists)
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testLateSaveResponseCannotClearNewLoginWarning() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.usePersistence("saveFailed")
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["Retry Saving"].waitForExistence(timeout: 10))
            backend.respond(path: "/session/save", status: 200, hold: true, body: #"{"state":"signedIn","persistence":"saved"}"#)
            app.buttons["Retry Saving"].click()
            waitForPending(backend)
            logOutFromAccount(app)
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            app.buttons["Sign in with Kite"].click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Sign-In Not Saved"].waitForExistence(timeout: 10))
            backend.releaseResponses()
            let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.pendingResponses == 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 5), .completed)
            XCTAssertTrue(app.staticTexts["Sign-In Not Saved"].exists)
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
        }

        func testUnfinishedLogoutSurvivesRelaunchBeforeAnySessionRestore() throws {
            for failure in [0, 503] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                backend.respond(path: "/logout", status: failure)
                logOutFromAccount(app)
                XCTAssertTrue(app.staticTexts["Couldn’t Finish Logging Out"].waitForExistence(timeout: 20))
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                XCTAssertFalse(app.staticTexts["Logout uncertainty"].exists)
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                let count = backend.requestedPaths.count
                app.terminate()
                backend.respond(path: "/logout", status: 200, hold: true, body: #"{"revocation":"unconfirmed"}"#)
                app.launch()
                waitForPending(backend)
                XCTAssertEqual(Array(backend.requestedPaths.dropFirst(count)), ["/logout"])
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                backend.releaseResponses()
                XCTAssertTrue(app.staticTexts["Logout uncertainty"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["Sign in with Kite"].isEnabled)
                app.terminate()
                app.launch()
                XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                beginLogin(app, backend: backend)
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                app.terminate()
                app.launch()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                XCTAssertEqual(backend.logouts, 2)
            }
        }

        private func logOutFromAccount(_ app: XCUIApplication) {
            app.buttons["Open Kite account"].click()
            XCTAssertTrue(app.sheets.firstMatch.buttons["Log Out"].waitForExistence(timeout: 5))
            app.sheets.firstMatch.buttons["Log Out"].click()
            XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
            app.sheets["alert"].buttons["Log Out"].click()
        }
    }
#endif
