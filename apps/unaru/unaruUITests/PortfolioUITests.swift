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
            app.typeKey(.upArrow, modifierFlags: [])
            XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Positions"].exists)
            XCTAssertTrue(app.staticTexts["Funds"].exists)
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
                XCTAssertTrue(app.outlines["Securities holdings"].waitForExistence(timeout: 5))
                app.outlines["Securities holdings"].staticTexts["STOCK"].click()
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
