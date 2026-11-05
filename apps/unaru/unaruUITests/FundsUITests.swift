//
//  FundsUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testFundsNavigationShowsSegmentBalancesAndKeyboardInspection() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/funds", status: 200, body: fundsFixture())
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Funds"].firstMatch.waitForExistence(timeout: 10))
                app.staticTexts["Funds"].firstMatch.click()
                XCTAssertTrue(app.staticTexts["Trading Funds"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Equity"].exists)
                XCTAssertTrue(app.staticTexts["Commodity — Disabled"].exists)
                XCTAssertTrue(app.staticTexts["Funds retrieval time"].exists)
                XCTAssertTrue(app.staticTexts["₹1,234.57"].exists)
                XCTAssertTrue(app.staticTexts["-₹25.00"].exists)
                app.buttons["Inspect Equity Funds"].click()
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts["Equity Funds Details"].waitForExistence(timeout: 5))
                for label in ["Cash (includes intraday pay-in)", "Collateral margin", "Unrealised intraday P&L", "SPAN margin"] {
                    XCTAssertTrue(sheet.descendants(matching: .any)[label].firstMatch.exists, label)
                }
                XCTAssertEqual(app.windows.firstMatch.frame.width, 1024, accuracy: 1)
                XCTAssertEqual(app.windows.firstMatch.frame.height, 846, accuracy: 1)
                capture(app, name: "Funds inspection - \(appearance)")
                sheet.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -600)
                XCTAssertTrue(sheet.descendants(matching: .any)["Payout"].firstMatch.isHittable)
                capture(app, name: "Funds utilisation - \(appearance)")
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
            }
        }
    }

    func fundsFixture(available: String = "1234.56789") -> String {
        """
        {"retrievedAt":815000000,"segments":[
          {"segment":"equity","enabled":true,"available":\(available),"utilised":-25,
           "availableComponents":{"cash":9000,"openingBalance":8000,"liveBalance":7000,"intradayPayin":1000,"adhocMargin":2000,"collateral":3000},
           "utilisedComponents":{"m2mUnrealised":-30,"m2mRealised":5,"debits":-25,"span":100,"optionPremium":10,"holdingSales":200,"exposure":20,"liquidCollateral":2,"delivery":3,"stockCollateral":4,"turnover":0,"payout":50}},
          {"segment":"commodity","enabled":false,"available":0,"utilised":0,"availableComponents":{},"utilisedComponents":{}}
        ]}
        """
    }
#endif
