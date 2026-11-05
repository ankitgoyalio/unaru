//
//  SupportingSourceRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testSupportingFailuresPreserveHoldingsTotalsAndRecoverIndependently() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
            backend.respond(path: "/portfolio/performance", status: 200, body: performanceFixture())
            backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture())
            backend.respond(path: "/portfolio/funds", status: 200, body: fundsFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Performance current value"].waitForExistence(timeout: 10))
            app.typeKey("n", modifierFlags: .command)
            let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
            let window = app.windows.element(boundBy: 0)
            let overview = app.windows.element(boundBy: 1)
            XCTAssertTrue(window.staticTexts["Performance current value"].waitForExistence(timeout: 10))
            window.staticTexts["Funds"].firstMatch.click()
            XCTAssertTrue(window.staticTexts["₹1,234.57"].waitForExistence(timeout: 5))
            window.staticTexts["Positions"].firstMatch.click()
            XCTAssertTrue(window.staticTexts["SHORTFUT"].waitForExistence(timeout: 5))
            backend.respond(path: "/portfolio/positions", status: 503, hold: true, body: #"{"code":"portfolioUnavailable"}"#)
            backend.respond(path: "/portfolio/funds", status: 503, hold: true, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            waitForPending(backend, path: "/portfolio/positions")
            waitForPending(backend, path: "/portfolio/funds")
            // Supporting sources are still pending while both holdings sources finish.
            XCTAssertTrue(overview.staticTexts["Performance current value"].waitForExistence(timeout: 10))
            XCTAssertTrue((overview.staticTexts["Performance current value"].value as? String ?? "").contains("2,000.00"))
            backend.respond(path: "/portfolio/positions", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            backend.releaseResponses(path: "/portfolio/positions")
            XCTAssertGreaterThan(backend.pendingResponses(for: "/portfolio/funds"), 0)
            window.staticTexts["Positions"].firstMatch.click()
            XCTAssertTrue(window.staticTexts["Stale positions — showing the previous retrieval."].waitForExistence(timeout: 5))
            XCTAssertTrue(window.staticTexts["SHORTFUT"].exists)
            XCTAssertTrue((overview.staticTexts["Performance current value"].value as? String ?? "").contains("2,000.00"))
            let oldPositionTime = retrievalText(window.staticTexts["Positions retrieval time"])
            let holdingsReads = backend.requestedPaths.filter { $0 == "/portfolio/holdings" || $0 == "/portfolio/mutual-funds" }.count
            let fundsReads = backend.requestedPaths.filter { $0 == "/portfolio/funds" }.count
            backend.respond(path: "/portfolio/positions", status: 200, hold: true, body: #"{"positions":[],"retrievedAt":815086400}"#)
            window.buttons["Retry Positions"].click()
            waitForPending(backend, path: "/portfolio/positions")
            XCTAssertTrue(window.descendants(matching: .any)["Loading positions…"].firstMatch.exists)
            XCTAssertTrue(window.staticTexts["SHORTFUT"].exists)
            XCTAssertEqual(retrievalText(window.staticTexts["Positions retrieval time"]), oldPositionTime)
            backend.respond(path: "/portfolio/positions", status: 200, body: #"{"positions":[],"retrievedAt":815086400}"#)
            backend.releaseResponses(path: "/portfolio/positions")
            XCTAssertTrue(window.staticTexts["No Positions"].waitForExistence(timeout: 5))
            XCTAssertFalse(window.staticTexts["SHORTFUT"].exists)
            XCTAssertNotEqual(retrievalText(window.staticTexts["Positions retrieval time"]), oldPositionTime)
            XCTAssertGreaterThan(backend.pendingResponses(for: "/portfolio/funds"), 0)
            XCTAssertEqual(backend.requestedPaths.filter { $0 == "/portfolio/funds" }.count, fundsReads)
            XCTAssertEqual(backend.requestedPaths.filter { $0 == "/portfolio/holdings" || $0 == "/portfolio/mutual-funds" }.count, holdingsReads)
            backend.respond(path: "/portfolio/funds", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            backend.releaseResponses(path: "/portfolio/funds")
            window.staticTexts["Funds"].firstMatch.click()
            XCTAssertTrue(window.staticTexts["Stale funds — showing the previous retrieval."].waitForExistence(timeout: 5))
            XCTAssertTrue(window.staticTexts["₹1,234.57"].exists)
            XCTAssertTrue((overview.staticTexts["Performance current value"].value as? String ?? "").contains("2,000.00"))
            let oldFundsTime = retrievalText(window.staticTexts["Funds retrieval time"])
            let positionReads = backend.requestedPaths.filter { $0 == "/portfolio/positions" }.count
            backend.respond(path: "/portfolio/funds", status: 200,
                            body: fundsFixture(available: "500").replacingOccurrences(of: "815000000", with: "815172800"))
            window.buttons["Retry Funds"].click()
            XCTAssertTrue(window.staticTexts["₹500.00"].waitForExistence(timeout: 5))
            XCTAssertFalse(window.staticTexts["Stale funds — showing the previous retrieval."].exists)
            XCTAssertNotEqual(retrievalText(window.staticTexts["Funds retrieval time"]), oldFundsTime)
            XCTAssertEqual(backend.requestedPaths.filter { $0 == "/portfolio/positions" }.count, positionReads)
            XCTAssertEqual(backend.requestedPaths.filter { $0 == "/portfolio/holdings" || $0 == "/portfolio/mutual-funds" }.count, holdingsReads)
            // The overview continues to use current successful holdings, including after supporting retries.
            XCTAssertTrue((overview.staticTexts["Performance current value"].value as? String ?? "").contains("2,000.00"))
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }

        func waitForPending(_ backend: ControlledBackend, path: String, file: StaticString = #filePath, line: UInt = #line) {
            let pending = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.pendingResponses(for: path) > 0 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 5), .completed, file: file, line: line)
        }

        func retrievalText(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> String {
            XCTAssertTrue(element.exists, file: file, line: line)
            let text = element.value as? String ?? element.label
            XCTAssertTrue(text.hasPrefix("Retrieved "), "Expected a readable retrieval time, got \(text)", file: file, line: line)
            return text
        }
    }
#endif
