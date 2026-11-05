//
//  PositionsRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testPositionsLoadingRecoveryAndEmptyRemainSeparateFromHoldings() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture())
            backend.respond(path: "/portfolio/positions", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
            app.staticTexts["Positions"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["Couldn’t refresh positions"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["No Positions"].exists)
            XCTAssertFalse(app.staticTexts["Positions retrieval time"].exists)
            backend.respond(path: "/portfolio/positions", status: 200, hold: true, body: positionsFixture())
            app.buttons["Retry Positions"].click()
            XCTAssertTrue(app.descendants(matching: .any)["Loading positions…"].firstMatch.waitForExistence(timeout: 5))
            waitForPending(backend)
            backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture())
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["SHORTFUT"].waitForExistence(timeout: 10))
            backend.respond(path: "/portfolio/positions", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Stale positions — showing the previous retrieval."].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["SHORTFUT"].exists)
            app.staticTexts["Holdings"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["STOCK"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Stale holdings — showing the previous retrieval."].exists)
            XCTAssertFalse(app.staticTexts["DELIVERY"].exists)
            app.staticTexts["Positions"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["Stale positions — showing the previous retrieval."].waitForExistence(timeout: 10))
            backend.respond(path: "/portfolio/positions", status: 200, body: #"{"positions":[],"retrievedAt":815000001}"#)
            app.buttons["Retry Positions"].click()
            XCTAssertTrue(app.staticTexts["No Positions"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["SHORTFUT"].exists)
            XCTAssertFalse(app.staticTexts["Stale positions — showing the previous retrieval."].exists)
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }

        func testPositionsRelaunchFetchesNewDataWithoutAnotherBrowserLogin() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
            app.staticTexts["Positions"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["SHORTFUT"].waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/portfolio/positions", status: 200, hold: true, body: positionsFixture(symbol: "FRESH"))
            app.launch()
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
            app.staticTexts["Positions"].firstMatch.click()
            waitForPending(backend)
            XCTAssertTrue(app.descendants(matching: .any)["Loading positions…"].firstMatch.exists)
            XCTAssertFalse(app.staticTexts["SHORTFUT"].exists)
            XCTAssertFalse(app.staticTexts["FRESH"].exists)
            backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture(symbol: "FRESH"))
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["FRESH"].waitForExistence(timeout: 10))
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }

        func testPositionsRejectSupersededSuccessAndFailure() throws {
            for obsoleteStatus in [200, 401] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture())
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
                app.staticTexts["Positions"].firstMatch.click()
                XCTAssertTrue(app.staticTexts["SHORTFUT"].waitForExistence(timeout: 10))
                let old = obsoleteStatus == 200 ? positionsFixture(symbol: "OBSOLETE") : #"{"code":"kiteSignInRequired"}"#
                backend.respond(path: "/portfolio/positions", status: obsoleteStatus, hold: true, body: old)
                app.typeKey("r", modifierFlags: .command)
                waitForPending(backend)
                backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture(symbol: "CURRENT"))
                app.typeKey("r", modifierFlags: .command)
                XCTAssertTrue(app.staticTexts["CURRENT"].waitForExistence(timeout: 10))
                backend.releaseResponses()
                let lost = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["CURRENT"])
                lost.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [lost], timeout: 3), .completed)
                XCTAssertFalse(app.staticTexts["OBSOLETE"].exists)
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
                XCTAssertEqual(backend.browserHandoffs, 1)
            }
        }

        func testPositionsAuthorityRemovalClearsEveryWindowAndRejectsOldAccount() throws {
            for expiry in [true, false] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture())
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
                app.staticTexts["Positions"].firstMatch.click()
                XCTAssertTrue(app.staticTexts["SHORTFUT"].waitForExistence(timeout: 10))
                app.typeKey("n", modifierFlags: .command)
                let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
                let second = app.windows.element(boundBy: 0)
                XCTAssertTrue(second.staticTexts["Portfolio Overview"].waitForExistence(timeout: 5))
                second.staticTexts["Positions"].firstMatch.click()
                XCTAssertTrue(second.staticTexts["SHORTFUT"].waitForExistence(timeout: 5))
                let old = expiry ? positionsFixture(symbol: "OBSOLETE") : #"{"code":"kiteSignInRequired"}"#
                backend.respond(path: "/portfolio/positions", status: expiry ? 200 : 401, hold: true, body: old)
                second.buttons["Refresh Portfolio"].click()
                waitForPending(backend)
                if expiry {
                    backend.respond(path: "/portfolio/positions", status: 401, body: #"{"code":"kiteSignInRequired"}"#)
                    second.buttons["Refresh Portfolio"].click()
                } else {
                    second.buttons["Open Kite account"].click()
                    second.sheets.firstMatch.buttons["Log Out"].click()
                    XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
                    app.sheets["alert"].buttons["Log Out"].click()
                }
                for window in app.windows.allElementsBoundByIndex {
                    XCTAssertTrue(window.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                    XCTAssertFalse(window.staticTexts["SHORTFUT"].exists)
                    XCTAssertFalse(window.buttons["Inspect Position"].exists)
                    XCTAssertFalse(window.buttons["Open Kite account"].exists)
                }
                backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture(symbol: "NEW-ACCOUNT"))
                app.buttons["Sign in with Kite"].firstMatch.click()
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["NEW-ACCOUNT"].firstMatch.waitForExistence(timeout: 10))
                backend.releaseResponses()
                let lost = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["NEW-ACCOUNT"].firstMatch)
                lost.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [lost], timeout: 3), .completed)
                XCTAssertFalse(app.staticTexts["OBSOLETE"].exists)
                XCTAssertFalse(app.staticTexts["SHORTFUT"].exists)
                XCTAssertEqual(app.buttons.matching(identifier: "Open Kite account").count, 2)
            }
        }
    }
#endif
