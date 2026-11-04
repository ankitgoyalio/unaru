//
//  LogoutUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 03/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testLogoutClearsEveryWindowBeforeRemoteCompletionAndAllowsSignIn() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
            // The standard File > New Window command opens another shared-session window.
            app.typeKey("n", modifierFlags: .command)
            let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
            for window in app.windows.allElementsBoundByIndex {
                window.buttons["Open Kite account"].click()
            }
            XCTAssertEqual(app.sheets.count, 2)
            backend.respond(path: "/logout", status: 200, hold: true, body: #"{"revocation":"confirmed"}"#)
            app.sheets.firstMatch.buttons["Log Out"].click()
            XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
            app.sheets["alert"].buttons["Log Out"].click()
            waitForPending(backend)
            XCTAssertTrue(app.sheets.containing(.staticText, identifier: "Kite account").firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "Open Kite account").count, 0)
            XCTAssertEqual(app.buttons.matching(identifier: "Sign in with Kite").count, 2)
            XCTAssertFalse(app.buttons["Sign in with Kite"].firstMatch.isEnabled)
            XCTAssertEqual(backend.logouts, 1)
            backend.releaseResponses()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["Sign in with Kite"].firstMatch.isEnabled }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            XCTAssertFalse(app.staticTexts["Logout uncertainty"].exists)
            app.buttons["Sign in with Kite"].firstMatch.click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["Open Kite account"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Open Configuration Folder"].exists)
        }

        func testUnconfirmedLogoutAndLateProfileCannotRestoreIdentity() throws {
            for outcome in [0, 200, 503] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend, revalidationInterval: "1")
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                backend.respond(path: "/profile", status: 200, hold: true, body: #"{"name":"Obsolete Person","userID":"OLD123"}"#)
                waitForPending(backend)
                app.buttons["Open Kite account"].click()
                XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
                backend.respond(path: "/logout", status: outcome, body: #"{"revocation":"unconfirmed"}"#)
                app.sheets.firstMatch.buttons["Log Out"].click()
                XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
                app.sheets["alert"].buttons["Log Out"].click()
                XCTAssertTrue(app.staticTexts["Logout uncertainty"].waitForExistence(timeout: 20))
                XCTAssertTrue(app.buttons["Sign in with Kite"].isEnabled)
                backend.releaseResponses()
                // This fixture may retain its old session after a transport failure.
                // No periodic verification may restore that authority after local logout.
                let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.pendingResponses == 0 }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed)
                XCTAssertFalse(accountIdentity(app, containing: "Obsolete Person").exists)
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                backend.respond(path: "/profile", status: 200)
                app.buttons["Sign in with Kite"].click()
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.staticTexts["Logout uncertainty"].exists)
            }
        }
    }
#endif
