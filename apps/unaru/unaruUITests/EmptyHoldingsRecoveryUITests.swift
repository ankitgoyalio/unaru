//
//  EmptyHoldingsRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testEitherHoldingsRetryCanReplaceStaleRowsWithEmptyAndRestoreTotals() throws {
            for securitiesFail in [true, false] {
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
                let path = securitiesFail ? "/portfolio/holdings" : "/portfolio/mutual-funds"
                let peer = securitiesFail ? "/portfolio/mutual-funds" : "/portfolio/holdings"
                let failure = securitiesFail ? "Couldn’t refresh securities holdings" : "Couldn’t refresh mutual fund holdings"
                backend.respond(path: path, status: 503, body: #"{"code":"portfolioUnavailable"}"#)
                app.typeKey("r", modifierFlags: .command)
                XCTAssertTrue(app.staticTexts[failure].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["Performance current value"].exists)
                let peerReads = backend.requestedPaths.filter { $0 == peer }.count
                backend.respond(path: path, status: 200, hold: true, body: #"{"readID":"empty-read","holdings":[],"retrievedAt":815086400}"#)
                backend.respond(path: "/portfolio/performance", status: 200, body: securitiesFail
                    ? #"{"sources":{"securitiesReadID":"empty-read","mutualFundsReadID":"funds-read"},"investedCost":100,"currentValue":200,"gain":100,"returnPercent":100,"matchedCost":100,"matchedValue":200,"totalHoldings":1,"costCount":1,"valueCount":1,"returnCount":1,"excludedMTFCount":0}"#
                    : #"{"sources":{"securitiesReadID":"securities-read","mutualFundsReadID":"empty-read"},"investedCost":1000,"currentValue":1200,"gain":200,"returnPercent":20,"matchedCost":1000,"matchedValue":1200,"totalHoldings":1,"costCount":1,"valueCount":1,"returnCount":1,"excludedMTFCount":0}"#)
                app.buttons[securitiesFail ? "Retry" : "Retry Mutual Funds"].click()
                waitForPending(backend, path: path)
                XCTAssertFalse(app.staticTexts["Performance current value"].exists)
                backend.releaseResponses(path: path)
                XCTAssertTrue(app.staticTexts["Performance current value"].waitForExistence(timeout: 5))
                XCTAssertTrue((app.staticTexts["Performance current value"].value as? String ?? "").contains(securitiesFail ? "₹200.00" : "₹1,200.00"))
                XCTAssertFalse(app.staticTexts[failure].exists)
                XCTAssertEqual(backend.requestedPaths.filter { $0 == peer }.count, peerReads)
                app.buttons["View Holdings"].click()
                XCTAssertTrue(app.staticTexts[securitiesFail ? "No Securities Holdings" : "No Mutual Fund Holdings"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts[securitiesFail ? "STOCK" : "Fractional Fund"].exists)
                XCTAssertEqual(backend.browserHandoffs, 1)
                XCTAssertEqual(backend.loginAttempts, 1)
            }
        }
    }
#endif
