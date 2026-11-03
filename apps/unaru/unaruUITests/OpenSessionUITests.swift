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
            let app = launch(backend: backend, revalidationInterval: "2")
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            backend.respond(path: "/profile", status: 401, body: "{\"code\":\"kiteSignInRequired\"}")
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            assertConnectionSheet(app)
            XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
            XCTAssertFalse(app.buttons["Retry"].exists)
            XCTAssertEqual(backend.loginAttempts, 1)
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testOpenAppRequestsLoginAfterBackendLosesSession() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend, revalidationInterval: "2")
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            app.buttons["Hide Sidebar"].click()
            backend.loseSession()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            assertConnectionSheet(app)
            XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
            let requests = backend.requests
            assertNoRequests(backend, after: requests)
            app.buttons["Sign in with Kite"].click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["Show Sidebar"].waitForExistence(timeout: 10))
            app.buttons["Show Sidebar"].click()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            XCTAssertEqual(backend.loginAttempts, 2)
        }

        func testOpenAppRetriesTransientFailuresWithoutAnotherLogin() throws {
            for (path, status) in [("/session", 0), ("/profile", 503)] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend, revalidationInterval: "2")
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
                let completed = backend.completedResponses
                backend.respond(path: path, status: status)
                let validation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.completedResponses > completed }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [validation], timeout: 20), .completed)
                let lostIdentity = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Open Kite account"])
                lostIdentity.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [lostIdentity], timeout: 3), .completed)
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
                XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                app.buttons["Open Kite account"].click()
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts["Couldn't refresh account details"].waitForExistence(timeout: 20))
                XCTAssertTrue(sheet.staticTexts["asha@example.invalid"].exists)
                backend.respond(path: path, status: 200)
                backend.useProfile(#"{"name":"Asha Rao","userID":"AB1234","email":"recovered@example.invalid"}"#)
                sheet.buttons["Retry"].click()
                XCTAssertTrue(sheet.staticTexts["recovered@example.invalid"].waitForExistence(timeout: 10))
                XCTAssertFalse(sheet.staticTexts["Couldn't refresh account details"].exists)
                sheet.buttons["Done"].click()
                // Retry also restores monitoring, rather than leaving another stale footer.
                backend.loseSession()
                XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                XCTAssertEqual(backend.loginAttempts, 1)
                XCTAssertEqual(backend.browserHandoffs, 1)
            }
        }

        private func assertNoRequests(_ backend: ControlledBackend, after count: Int) {
            let extra = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.requests > count }, object: nil)
            extra.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [extra], timeout: 3), .completed)
        }
    }
#endif
