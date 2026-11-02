//
//  AccountRefreshUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 02/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testNewSheetRefreshSupersedesHeldBackgroundProfile() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend, revalidationInterval: "2")
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
            backend.respond(path: "/profile", status: 200, hold: true,
                            body: #"{"name":"Obsolete Person","userID":"OLD123"}"#)
            waitForPending(backend)
            backend.respond(path: "/profile", status: 200,
                            body: #"{"name":"Current Person","userID":"NEW123","email":"current@example.invalid"}"#)
            app.buttons["Open Kite account"].click()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.staticTexts["current@example.invalid"].waitForExistence(timeout: 10))
            backend.releaseResponses()
            let obsolete = sheet.staticTexts["Obsolete Person"]
            let rejected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: obsolete)
            rejected.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [rejected], timeout: 3), .completed)
            XCTAssertTrue(sheet.staticTexts["Current Person"].exists)
            XCTAssertTrue(sheet.staticTexts["NEW123"].exists)
        }

        func testExpiryClearsEveryWindowAndRejectsHeldRefresh() throws {
            for explicitProviderExpiry in [true, false] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                app.typeKey("n", modifierFlags: .command)
                let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
                let first = app.windows.element(boundBy: 0)
                let second = app.windows.element(boundBy: 1)
                backend.respond(path: "/profile", status: 200, hold: true,
                                body: #"{"name":"Obsolete Person","userID":"OLD123"}"#)
                first.buttons["Open Kite account"].click()
                XCTAssertTrue(first.sheets.firstMatch.waitForExistence(timeout: 5))
                waitForPending(backend)
                if explicitProviderExpiry {
                    backend.respond(path: "/profile", status: 403, body: #"{"code":"kiteSignInRequired"}"#)
                } else {
                    backend.loseSession()
                }
                second.buttons["Open Kite account"].click()
                for window in app.windows.allElementsBoundByIndex {
                    XCTAssertTrue(window.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                    XCTAssertFalse(window.sheets.firstMatch.exists)
                    XCTAssertFalse(window.buttons["Open Kite account"].exists)
                    XCTAssertFalse(window.staticTexts["Asha Rao"].exists)
                }
                backend.respond(path: "/profile", status: 200)
                backend.releaseResponses()
                let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.buttons["Open Kite account"].firstMatch)
                restored.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 3), .completed)
                XCTAssertFalse(app.staticTexts["Obsolete Person"].exists)
                XCTAssertEqual(backend.loginAttempts, 1)
            }
        }

        func testSheetRefreshDoesNotTreatInternalAuthorizationAsKiteExpiry() throws {
            for status in [401, 403] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["Open Kite account"].waitForExistence(timeout: 10))
                backend.respond(path: "/profile", status: status, body: "{}")
                app.buttons["Open Kite account"].click()
                XCTAssertTrue(app.staticTexts["Unaru Couldn’t Start"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.sheets.firstMatch.exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            }
        }
    }
#endif
