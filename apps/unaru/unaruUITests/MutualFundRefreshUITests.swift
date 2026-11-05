//
//  MutualFundRefreshUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testMutualFundLoadingFailureStaleRecoveryAndSourceSpecificRetry() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 503, hold: true, body: #"{"code":"portfolioUnavailable"}"#)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.descendants(matching: .any)["Loading mutual fund holdings…"].firstMatch.waitForExistence(timeout: 10))
            app.buttons["View Holdings"].click()
            XCTAssertTrue(app.staticTexts["STOCK"].waitForExistence(timeout: 10))
            waitForPending(backend)
            XCTAssertFalse(app.staticTexts["Mutual funds retrieval time"].exists)
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["Couldn’t refresh mutual fund holdings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["No Mutual Fund Holdings"].exists)
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: mutualFundFixture())
            backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture(symbol: "UNREQUESTED"))
            app.scrollViews["Portfolio content"].scroll(byDeltaX: 0, deltaY: -500)
            app.buttons["Retry Mutual Funds"].click()
            XCTAssertTrue(app.staticTexts["Sample Growth Fund"].waitForExistence(timeout: 10))
            let lostSecurities = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["STOCK"])
            lostSecurities.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [lostSecurities], timeout: 2), .completed)
            XCTAssertFalse(app.staticTexts["UNREQUESTED"].exists)
            backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture(symbol: "CURRENT-SECURITY"))
            backend.respond(path: "/portfolio/mutual-funds", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["CURRENT-SECURITY"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Stale mutual funds — showing the previous retrieval."].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Sample Growth Fund"].exists)
            XCTAssertTrue(app.staticTexts["Mutual funds retrieval time"].exists)
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: #"{"holdings":[],"retrievedAt":815000002}"#)
            app.scrollViews["Portfolio content"].scroll(byDeltaX: 0, deltaY: -500)
            app.buttons["Retry Mutual Funds"].click()
            XCTAssertTrue(app.staticTexts["No Mutual Fund Holdings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Sample Growth Fund"].exists)
            XCTAssertFalse(app.staticTexts["Stale mutual funds — showing the previous retrieval."].exists)
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }
    }
#endif
