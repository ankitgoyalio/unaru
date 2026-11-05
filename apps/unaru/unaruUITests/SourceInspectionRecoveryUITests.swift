//
//  SourceInspectionRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testOpenHoldingInspectionShowsPendingStaleRetrievalAndRetry() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
            app.buttons["View Holdings"].click()
            let table = app.outlines["Holdings"]
            XCTAssertTrue(table.staticTexts["STOCK"].waitForExistence(timeout: 5))
            table.staticTexts["STOCK"].click()
            app.typeKey(.return, modifierFlags: [])
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.staticTexts["Holding Details"].waitForExistence(timeout: 5))
            let retrieved = sheet.staticTexts["Inspection source retrieval time"]
            XCTAssertTrue(retrieved.exists)
            let previousTime = retrievalText(retrieved)
            backend.respond(path: "/portfolio/holdings", status: 503, hold: true, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            waitForPending(backend)
            XCTAssertTrue(sheet.descendants(matching: .any)["Refreshing source…"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.staticTexts["Showing the previous retrieval while refreshing."].exists)
            XCTAssertEqual(retrievalText(retrieved), previousTime)
            backend.releaseResponses()
            XCTAssertTrue(sheet.staticTexts["Stale data — showing the previous retrieval."].waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.buttons["Retry Securities"].isEnabled)
            XCTAssertEqual(retrievalText(retrieved), previousTime)
            XCTAssertTrue(sheet.staticTexts["Price valuation date unavailable"].firstMatch.exists)
            capture(app, name: "Stale securities inspection")
            backend.respond(path: "/portfolio/holdings", status: 200, body: #"{"holdings":[],"retrievedAt":815000001}"#)
            sheet.buttons["Retry Securities"].click()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["No Securities Holdings"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["STOCK"].exists)
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }

        func testOtherSourceInspectionsKeepRetrievalAndRecoveryVisible() throws {
            let sources = [
                (path: "/portfolio/mutual-funds", fixture: mutualFundFixture(), destination: "Holdings", row: "Sample Growth Fund",
                 inspect: "Inspect Mutual Fund", title: "Mutual Fund Details", retry: "Retry Mutual Funds",
                 empty: #"{"holdings":[],"retrievedAt":815086400}"#, emptyTitle: "No Mutual Fund Holdings"),
                (path: "/portfolio/positions", fixture: positionsFixture(), destination: "Positions", row: "SHORTFUT",
                 inspect: "Inspect Position", title: "Position Details", retry: "Retry Positions",
                 empty: #"{"positions":[],"retrievedAt":815086400}"#, emptyTitle: "No Positions"),
                (path: "/portfolio/funds", fixture: fundsFixture(), destination: "Funds", row: "₹1,234.57",
                 inspect: "Inspect Equity Funds", title: "Equity Funds Details", retry: "Retry Funds",
                 empty: #"{"segments":[],"retrievedAt":815086400}"#, emptyTitle: "No Trading Funds"),
            ]
            for source in sources {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: source.path, status: 200, body: source.fixture)
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
                app.staticTexts[source.destination].firstMatch.click()
                XCTAssertTrue(app.staticTexts[source.row].waitForExistence(timeout: 5))
                if source.destination != "Funds" {
                    app.staticTexts[source.row].click()
                    app.typeKey(.return, modifierFlags: [])
                } else {
                    app.buttons[source.inspect].click()
                }
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts[source.title].waitForExistence(timeout: 5))
                let retrieved = sheet.staticTexts["Inspection source retrieval time"]
                XCTAssertTrue(retrieved.exists, source.path)
                let previousTime = retrievalText(retrieved)
                backend.respond(path: source.path, status: 503, hold: true, body: #"{"code":"portfolioUnavailable"}"#)
                app.typeKey("r", modifierFlags: .command)
                waitForPending(backend, path: source.path)
                XCTAssertTrue(sheet.descendants(matching: .any)["Refreshing source…"].firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(sheet.staticTexts["Showing the previous retrieval while refreshing."].exists)
                backend.releaseResponses(path: source.path)
                XCTAssertTrue(sheet.staticTexts["Stale data — showing the previous retrieval."].waitForExistence(timeout: 5))
                XCTAssertEqual(retrievalText(retrieved), previousTime)
                capture(app, name: "Stale inspection - \(source.destination)")
                if source.destination == "Holdings" {
                    XCTAssertTrue(sheet.staticTexts["2026-11-03"].exists)
                } else if source.destination == "Positions" {
                    XCTAssertTrue(sheet.staticTexts["Price valuation date unavailable"].exists)
                }
                backend.respond(path: source.path, status: 200, body: source.empty)
                sheet.buttons[source.retry].click()
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts[source.emptyTitle].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts[source.row].exists)
                XCTAssertEqual(backend.browserHandoffs, 1)
                XCTAssertEqual(backend.loginAttempts, 1)
            }
        }
    }
#endif
