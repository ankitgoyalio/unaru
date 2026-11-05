//
//  MutualFundAuthorityUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testMutualFundsRejectsSupersededSuccessAndFailure() throws {
            for obsoleteStatus in [200, 401] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: mutualFundFixture())
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
                app.buttons["View Holdings"].click()
                XCTAssertTrue(app.staticTexts["Sample Growth Fund"].waitForExistence(timeout: 10))
                let obsolete = obsoleteStatus == 200 ? mutualFundFixture(name: "OBSOLETE") : #"{"code":"kiteSignInRequired"}"#
                backend.respond(path: "/portfolio/mutual-funds", status: obsoleteStatus, hold: true, body: obsolete)
                app.typeKey("r", modifierFlags: .command)
                waitForPending(backend)
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: mutualFundFixture(name: "CURRENT"))
                app.typeKey("r", modifierFlags: .command)
                XCTAssertTrue(app.staticTexts["CURRENT"].waitForExistence(timeout: 10))
                backend.releaseResponses()
                let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["CURRENT"])
                replaced.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 3), .completed)
                XCTAssertFalse(app.staticTexts["OBSOLETE"].exists)
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
                XCTAssertEqual(backend.browserHandoffs, 1)
            }
        }

        func testMutualFundsAuthorityRemovalClearsWindowsAndRejectsOldResponses() throws {
            for expiry in [true, false] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: mutualFundFixture())
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
                app.buttons["View Holdings"].click()
                XCTAssertTrue(app.staticTexts["Sample Growth Fund"].waitForExistence(timeout: 10))
                app.typeKey("n", modifierFlags: .command)
                let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
                let second = app.windows.element(boundBy: 0)
                XCTAssertTrue(second.buttons["View Holdings"].waitForExistence(timeout: 5))
                second.buttons["View Holdings"].click()
                XCTAssertTrue(second.staticTexts["Sample Growth Fund"].waitForExistence(timeout: 5))
                let inspectionWindow = second
                inspectionWindow.outlines["Holdings"].staticTexts["Sample Growth Fund"].click()
                inspectionWindow.buttons["Inspect Holding"].click()
                XCTAssertTrue(inspectionWindow.sheets.firstMatch.staticTexts["Mutual Fund Details"].waitForExistence(timeout: 5))
                let oldBody = expiry ? mutualFundFixture(name: "OBSOLETE") : #"{"code":"kiteSignInRequired"}"#
                backend.respond(path: "/portfolio/mutual-funds", status: expiry ? 200 : 401, hold: true, body: oldBody)
                app.typeKey("r", modifierFlags: .command)
                waitForPending(backend)
                if expiry {
                    backend.respond(path: "/portfolio/mutual-funds", status: 401, body: #"{"code":"kiteSignInRequired"}"#)
                    app.typeKey("r", modifierFlags: .command)
                } else {
                    app.typeKey("`", modifierFlags: .command)
                    let removalWindow = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { !$0.sheets.firstMatch.exists })
                    removalWindow.buttons["Open Kite account"].click()
                    XCTAssertTrue(app.buttons["Log Out"].waitForExistence(timeout: 5))
                    app.buttons["Log Out"].click()
                    XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
                    app.sheets["alert"].buttons["Log Out"].click()
                }
                for window in app.windows.allElementsBoundByIndex {
                    XCTAssertTrue(window.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                    XCTAssertFalse(window.staticTexts["Sample Growth Fund"].exists)
                    XCTAssertFalse(window.buttons["Inspect Holding"].exists)
                    XCTAssertFalse(window.staticTexts["Mutual Fund Details"].exists)
                    XCTAssertFalse(window.buttons["Open Kite account"].exists)
                }
                // New authority is established before either obsolete outcome is released.
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: mutualFundFixture(name: "NEW-ACCOUNT"))
                app.buttons["Sign in with Kite"].firstMatch.click()
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["NEW-ACCOUNT"].firstMatch.waitForExistence(timeout: 10))
                backend.releaseResponses()
                let lost = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["NEW-ACCOUNT"].firstMatch)
                lost.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [lost], timeout: 3), .completed)
                XCTAssertFalse(app.staticTexts["OBSOLETE"].exists)
                XCTAssertFalse(app.staticTexts["Sample Growth Fund"].exists)
                XCTAssertEqual(app.buttons.matching(identifier: "Open Kite account").count, 2)
            }
        }

        func testMutualFundsRelaunchLoadsFreshSourceWithoutBrowserSignIn() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.usePersistence("saved")
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: mutualFundFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
            app.buttons["View Holdings"].click()
            XCTAssertTrue(app.staticTexts["Sample Growth Fund"].waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/portfolio/mutual-funds", status: 200, hold: true, body: mutualFundFixture(name: "FRESH"))
            app.launch()
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
            waitForPending(backend)
            XCTAssertFalse(app.staticTexts["Sample Growth Fund"].exists)
            app.buttons["View Holdings"].click()
            XCTAssertFalse(app.staticTexts["FRESH"].exists)
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["FRESH"].waitForExistence(timeout: 10))
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }
    }
#endif
