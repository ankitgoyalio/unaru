//
//  PerformanceRefreshUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testPerformanceWithholdsMixedRefreshTotalsAndRecoversOnlyFailedSource() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
            backend.respond(path: "/portfolio/performance", status: 200, body: performanceFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Performance current value"].waitForExistence(timeout: 10))
            backend.respond(path: "/portfolio/holdings", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Couldn’t refresh securities holdings"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Stale holdings — showing the previous retrieval."].exists)
            XCTAssertTrue(app.staticTexts["Combined totals unavailable until both holdings sources refresh successfully."].exists)
            XCTAssertFalse(app.staticTexts["Performance current value"].exists)
            // A second failed source in a newer full refresh must not reuse either earlier success.
            backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Couldn’t refresh mutual fund holdings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Performance current value"].exists)
            // Securities must not be fetched by Retry Mutual Funds.
            let reads = backend.requestedPaths.filter { $0 == "/portfolio/holdings" }.count
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
            backend.respond(path: "/portfolio/performance", status: 200, body: performanceFixture(value: 2100))
            app.buttons["Retry Mutual Funds"].click()
            XCTAssertTrue(app.staticTexts["Performance current value"].waitForExistence(timeout: 10))
            XCTAssertTrue((app.staticTexts["Performance current value"].value as? String ?? "").contains("2,100.00"))
            XCTAssertEqual(backend.requestedPaths.filter { $0 == "/portfolio/holdings" }.count, reads)
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
        }

        func testPerformanceRejectsObsoleteAggregateSuccessAndAuthorityFailure() throws {
            for status in [200, 401] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
                backend.respond(path: "/portfolio/performance", status: status, hold: true,
                                body: status == 200 ? performanceFixture(value: 9999) : #"{"code":"kiteSignInRequired"}"#)
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                waitForPending(backend)
                backend.respond(path: "/portfolio/performance", status: 200, body: performanceFixture())
                app.typeKey("r", modifierFlags: .command)
                XCTAssertTrue(app.staticTexts["Performance current value"].waitForExistence(timeout: 10))
                backend.releaseResponses()
                let lost = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Performance current value"])
                lost.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [lost], timeout: 3), .completed)
                XCTAssertTrue((app.staticTexts["Performance current value"].value as? String ?? "").contains("2,000.00"))
                XCTAssertEqual(backend.browserHandoffs, 1)
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
            }
        }

        func testPerformanceAuthorityRemovalClearsWindowsAndRejectsOldAggregate() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
            backend.respond(path: "/portfolio/performance", status: 200, body: performanceFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Performance current value"].waitForExistence(timeout: 10))
            app.typeKey("n", modifierFlags: .command)
            let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
            XCTAssertTrue(app.windows.element(boundBy: 0).staticTexts["Performance current value"].waitForExistence(timeout: 10))
            backend.respond(path: "/portfolio/performance", status: 401, hold: true, body: #"{"code":"kiteSignInRequired"}"#)
            app.typeKey("r", modifierFlags: .command)
            waitForPending(backend)
            app.buttons["Open Kite account"].firstMatch.click()
            app.sheets.firstMatch.buttons["Log Out"].click()
            XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
            app.sheets["alert"].buttons["Log Out"].click()
            for window in app.windows.allElementsBoundByIndex {
                XCTAssertTrue(window.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                XCTAssertFalse(window.staticTexts["Performance current value"].exists)
            }
            backend.respond(path: "/portfolio/performance", status: 200, body: performanceFixture(value: 2300))
            app.buttons["Sign in with Kite"].firstMatch.click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Performance current value"].firstMatch.waitForExistence(timeout: 10))
            backend.releaseResponses()
            let lost = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Performance current value"].firstMatch)
            lost.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [lost], timeout: 3), .completed)
            XCTAssertTrue((app.staticTexts["Performance current value"].firstMatch.value as? String ?? "").contains("2,300.00"))
            XCTAssertEqual(app.buttons.matching(identifier: "Open Kite account").count, 2)
        }
    }
#endif
