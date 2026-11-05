//
//  FundsRefreshUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testFundsFailureIsIndependentAndRetryRetainsStaleBalances() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture())
            backend.respond(path: "/portfolio/funds", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
            app.buttons["View Holdings"].click()
            XCTAssertTrue(app.staticTexts["STOCK"].waitForExistence(timeout: 5))
            app.staticTexts["Funds"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["Couldn’t refresh trading funds"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["No Trading Funds"].exists)
            XCTAssertFalse(app.staticTexts["Funds retrieval time"].exists)
            backend.respond(path: "/portfolio/funds", status: 200, body: fundsFixture())
            app.buttons["Retry Funds"].click()
            XCTAssertTrue(app.staticTexts["₹1,234.57"].waitForExistence(timeout: 5))
            backend.respond(path: "/portfolio/funds", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Stale funds — showing the previous retrieval."].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["₹1,234.57"].exists)
            app.staticTexts["Holdings"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["STOCK"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Couldn’t refresh securities holdings"].exists)
            app.staticTexts["Funds"].firstMatch.click()
            backend.respond(path: "/portfolio/funds", status: 200, body: #"{"segments":[],"retrievedAt":815000001}"#)
            app.buttons["Retry Funds"].click()
            XCTAssertTrue(app.staticTexts["No Trading Funds"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Stale funds — showing the previous retrieval."].exists)
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testFundsLoadingDisabledAndAbsentSegmentsAreDistinct() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/funds", status: 200, hold: true,
                            body: #"{"segments":[{"segment":"equity","enabled":false,"available":0,"utilised":0,"availableComponents":{},"utilisedComponents":{}}],"retrievedAt":815000000}"#)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Funds"].firstMatch.waitForExistence(timeout: 10))
            app.staticTexts["Funds"].firstMatch.click()
            XCTAssertTrue(app.descendants(matching: .any)["Loading trading funds…"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["No Trading Funds"].exists)
            waitForPending(backend)
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["No Enabled Trading Segments"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Equity — Disabled"].exists)
            XCTAssertTrue(app.staticTexts["Commodity — Not reported by Kite"].exists)
            XCTAssertFalse(app.staticTexts["Couldn’t refresh trading funds"].exists)
            XCTAssertFalse(app.buttons["Inspect Equity Funds"].exists)
        }

        func testFundsRejectsSupersededSuccessAndFailure() throws {
            for obsoleteStatus in [200, 401] {
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
                let old = obsoleteStatus == 200 ? fundsFixture(available: "999") : #"{"code":"kiteSignInRequired"}"#
                backend.respond(path: "/portfolio/funds", status: obsoleteStatus, hold: true, body: old)
                app.typeKey("r", modifierFlags: .command)
                waitForPending(backend)
                backend.respond(path: "/portfolio/funds", status: 200, body: fundsFixture(available: "500"))
                app.typeKey("r", modifierFlags: .command)
                XCTAssertTrue(app.staticTexts["₹500.00"].waitForExistence(timeout: 5))
                backend.releaseResponses()
                let lost = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["₹500.00"])
                lost.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [lost], timeout: 3), .completed)
                XCTAssertFalse(app.staticTexts["₹999.00"].exists)
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
                XCTAssertEqual(backend.browserHandoffs, 1)
            }
        }
    }
#endif
