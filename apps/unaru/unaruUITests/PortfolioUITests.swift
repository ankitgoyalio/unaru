//
//  PortfolioUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testPortfolioDefaultsToOverviewAndLoadsHoldings() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, hold: true,
                            body: #"{"holdings":[],"retrievedAt":815000000}"#)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["Loading securities holdings…"].firstMatch.waitForExistence(timeout: 5))
            waitForPending(backend)
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["No Securities Holdings"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
            XCTAssertTrue(app.buttons["Refresh Portfolio"].isEnabled)
            app.staticTexts["Holdings"].firstMatch.click()
            XCTAssertTrue(app.staticTexts["Securities Holdings"].waitForExistence(timeout: 5))
            backend.respond(path: "/portfolio/holdings", status: 200, body: #"{"holdings":[],"retrievedAt":815000001}"#)
            // Keep keyboard navigation in the sidebar after the detail controls finish loading.
            app.staticTexts["Holdings"].firstMatch.click()
            app.typeKey(.upArrow, modifierFlags: [])
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Positions"].exists)
            XCTAssertTrue(app.staticTexts["Funds"].exists)
        }

        func testNewAuthorityResetsEveryWindowToPortfolioWithoutResettingRevalidation() throws {
            for expiry in [false, true] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture())
                let app = launch(backend: backend, revalidationInterval: "2")
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
                app.staticTexts["Positions"].firstMatch.click()
                app.typeKey("n", modifierFlags: .command)
                let windows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.windows.count == 2 }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [windows], timeout: 5), .completed)
                let fundsWindow = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.staticTexts["Portfolio Overview"].exists })
                let positionsWindow = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.staticTexts["Current Net Positions"].exists })
                fundsWindow.staticTexts["Funds"].firstMatch.click()
                backend.respond(path: "/profile", status: 200, body: #"{"name":"Revalidated Person","userID":"AB1234"}"#)
                XCTAssertTrue(accountIdentity(app, containing: "Revalidated Person").waitForExistence(timeout: 10))
                XCTAssertTrue(positionsWindow.staticTexts["Current Net Positions"].exists)
                XCTAssertTrue(fundsWindow.staticTexts["Trading Funds"].exists)
                if expiry {
                    backend.respond(path: "/profile", status: 401, body: #"{"code":"kiteSignInRequired"}"#)
                } else {
                    fundsWindow.buttons["Open Kite account"].click()
                    XCTAssertTrue(app.buttons["Log Out"].waitForExistence(timeout: 5))
                    app.buttons["Log Out"].click()
                    XCTAssertTrue(app.sheets["alert"].waitForExistence(timeout: 5))
                    app.sheets["alert"].buttons["Log Out"].click()
                }
                for window in app.windows.allElementsBoundByIndex {
                    XCTAssertTrue(window.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
                }
                backend.respond(path: "/profile", status: 200)
                backend.respond(path: "/portfolio/holdings", status: 200, hold: true, body: portfolioFixture(symbol: "NEW-AUTHORITY"))
                app.buttons["Sign in with Kite"].firstMatch.click()
                waitForHandoff(backend, count: 2)
                backend.completeLogin()
                for window in app.windows.allElementsBoundByIndex {
                    XCTAssertTrue(window.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
                }
                waitForPending(backend)
                backend.releaseResponses()
                XCTAssertTrue(app.staticTexts["1 securities holdings"].firstMatch.waitForExistence(timeout: 10))
            }
        }

        func testHoldingsKeyboardInspectionShowsSourceFieldsAndLimitations() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture())
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
                app.buttons["View Holdings"].click()
                XCTAssertTrue(app.outlines["Holdings"].waitForExistence(timeout: 5))
                app.outlines["Holdings"].staticTexts["STOCK"].click()
                app.typeKey(.return, modifierFlags: [])
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts["Holding Details"].waitForExistence(timeout: 5))
                for label in ["Kite securities holdings", "Unknown investment type", "Name unavailable", "TEST-ISIN",
                              "Ordinary quantity (Kite)", "T1 quantity", "Used quantity", "Collateral quantity",
                              "MTF — Broker Reported", "Gross value", "Initial margin", "Price valuation date unavailable",
                              "Collateral relationship unavailable", "MTF sale reconciliation unavailable"]
                {
                    XCTAssertTrue(sheet.descendants(matching: .any)[label].firstMatch.exists, label)
                }
                XCTAssertTrue(sheet.staticTexts["60"].firstMatch.exists)
                XCTAssertTrue(sheet.staticTexts["40"].exists)
                XCTAssertTrue(sheet.staticTexts["5"].exists)
                XCTAssertEqual(app.windows.firstMatch.frame.width, 1024, accuracy: 1)
                XCTAssertEqual(app.windows.firstMatch.frame.height, 846, accuracy: 1)
                capture(app, name: "Holding inspection - \(appearance)")
                sheet.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -600)
                XCTAssertTrue(sheet.descendants(matching: .any)["MTF — Broker Reported"].firstMatch.isHittable)
                capture(app, name: "MTF and limitations - \(appearance)")
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
            }
        }
    }
#endif

#if os(macOS)
    /// The same credential-free contract emitted by the protected backend operation.
    func portfolioFixture(symbol: String = "STOCK") -> String {
        """
        {"retrievedAt":815000000,"holdings":[{
          "id":"0","symbol":"\(symbol)","exchange":"NSE","instrumentToken":123,"isin":"TEST-ISIN","product":"CNC",
          "investmentType":"unknown","quantity":60,"t1Quantity":5,"realisedQuantity":60,"authorisedQuantity":60,
          "openingQuantity":100,"usedQuantity":40,"shortQuantity":2,"collateralQuantity":7,"collateralType":"pledge",
          "discrepancy":false,"averagePrice":100.123456789,"lastPrice":125.125,
          "mtf":{"quantity":10,"usedQuantity":3,"averagePrice":100,"value":1250,"initialMargin":300},
          "limitations":["nameUnavailable","classificationUnavailable","valuationDateUnavailable","collateralRelationshipUnknown","mtfRelationshipUnknown"]
        }]}
        """
    }
#endif
