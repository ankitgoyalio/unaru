//
//  CancellationRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 04/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testUnfinishedCancellationSurvivesRelaunchAndRejectsDelayedIdentity() throws {
            for failure in [0, 503] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.respond(path: "/login/ui-attempt-1", status: 200, hold: true,
                                body: #"{"state":"signedIn","profile":{"name":"Asha Rao","userID":"AB1234"},"persistence":"saved"}"#)
                backend.completeLogin()
                waitForPending(backend)
                // The helper has validated and saved authority, but its signedIn
                // status has not reached the app when the user cancels.
                backend.respond(path: "/login/ui-attempt-1", status: failure)
                app.buttons["Cancel Sign-In"].click()
                XCTAssertTrue(app.staticTexts["Couldn’t Finish Cancelling Sign-In"].waitForExistence(timeout: 20))
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                XCTAssertFalse(app.staticTexts["Logout uncertainty"].exists)
                backend.releaseResponses()
                XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
                let beforeRetry = backend.requestedPaths.count
                app.buttons["Retry Cancellation"].click()
                let retried = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    backend.requestedPaths.count > beforeRetry && app.buttons["Retry Cancellation"].exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [retried], timeout: 20), .completed)
                let count = backend.requestedPaths.count
                app.terminate()
                backend.respond(path: "/login/ui-attempt-1", status: 200, hold: true)
                app.launch()
                waitForPending(backend)
                XCTAssertEqual(Array(backend.requestedPaths.dropFirst(count)), ["/login/ui-attempt-1"])
                XCTAssertTrue(app.staticTexts["Cancelling Sign-In…"].exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].isEnabled)
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                backend.releaseResponses()
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["Sign in with Kite"].isEnabled }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
                XCTAssertFalse(app.staticTexts["Logout uncertainty"].exists)
                app.terminate()
                app.launch()
                XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                beginLogin(app, backend: backend)
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                app.terminate()
                app.launch()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                XCTAssertEqual(backend.logouts, 0)
            }
        }
    }
#endif
