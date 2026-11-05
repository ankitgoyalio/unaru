//
//  FundsAuthorityUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testFundsAuthorityRemovalClearsWindowsAndRejectsOldResponses() throws {
            for expiry in [true, false] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/funds", status: 200, body: fundsFixture())
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Funds"].firstMatch.waitForExistence(timeout: 10))
                app.staticTexts["Funds"].firstMatch.click()
                XCTAssertTrue(app.staticTexts["₹1,234.57"].waitForExistence(timeout: 5))
                app.typeKey("n", modifierFlags: .command)
                let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
                let second = app.windows.element(boundBy: 0)
                second.staticTexts["Funds"].firstMatch.click()
                XCTAssertTrue(second.staticTexts["₹1,234.57"].waitForExistence(timeout: 5))
                second.buttons["Inspect Equity Funds"].click()
                XCTAssertTrue(second.sheets.firstMatch.staticTexts["Equity Funds Details"].waitForExistence(timeout: 5))
                let old = expiry ? fundsFixture(available: "999") : #"{"code":"kiteSignInRequired"}"#
                backend.respond(path: "/portfolio/funds", status: expiry ? 200 : 401, hold: true, body: old)
                if !expiry {
                    app.typeKey(.escape, modifierFlags: [])
                }
                app.typeKey("r", modifierFlags: .command)
                waitForPending(backend)
                if expiry {
                    backend.respond(path: "/portfolio/funds", status: 401, body: #"{"code":"kiteSignInRequired"}"#)
                    app.typeKey("r", modifierFlags: .command)
                } else {
                    second.buttons["Open Kite account"].click()
                    second.sheets.firstMatch.buttons["Log Out"].click()
                    XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
                    app.sheets["alert"].buttons["Log Out"].click()
                }
                for window in app.windows.allElementsBoundByIndex {
                    XCTAssertTrue(window.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                    XCTAssertFalse(window.staticTexts["₹1,234.57"].exists)
                    XCTAssertFalse(window.buttons["Inspect Equity Funds"].exists)
                    XCTAssertFalse(window.staticTexts["Equity Funds Details"].exists)
                }
                backend.respond(path: "/portfolio/funds", status: 200, body: fundsFixture(available: "500"))
                app.buttons["Sign in with Kite"].firstMatch.click()
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["₹500.00"].firstMatch.waitForExistence(timeout: 10))
                backend.releaseResponses()
                let lost = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["₹500.00"].firstMatch)
                lost.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [lost], timeout: 3), .completed)
                XCTAssertFalse(app.staticTexts["₹999.00"].exists)
                XCTAssertEqual(app.buttons.matching(identifier: "Open Kite account").count, 2)
            }
        }

        func testFundsRelaunchLoadsFreshBalancesWithoutBrowserLogin() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.usePersistence("saved")
            backend.respond(path: "/portfolio/funds", status: 200, body: fundsFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Funds"].firstMatch.waitForExistence(timeout: 10))
            app.staticTexts["Funds"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["₹1,234.57"].waitForExistence(timeout: 5))
            app.terminate()
            backend.respond(path: "/portfolio/funds", status: 200, hold: true, body: fundsFixture(available: "500"))
            app.launch()
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
            waitForPending(backend)
            app.staticTexts["Funds"].firstMatch.click()
            XCTAssertFalse(app.staticTexts["₹1,234.57"].exists)
            XCTAssertFalse(app.staticTexts["₹500.00"].exists)
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["₹500.00"].waitForExistence(timeout: 5))
            XCTAssertEqual(backend.browserHandoffs, 1)
        }
    }
#endif
