//
//  MutualFundUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testMutualFundsShowFractionalUnitsDatesAndKeyboardInspection() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture())
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: mutualFundFixture())
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
                app.buttons["View Holdings"].click()
                XCTAssertTrue(app.staticTexts["STOCK"].waitForExistence(timeout: 10))
                let table = app.outlines["Mutual fund holdings"]
                XCTAssertTrue(table.waitForExistence(timeout: 5))
                for value in ["Sample Growth Fund", "12.345678901", "2026-11-03", "2026-11-02", "Unavailable"] {
                    XCTAssertTrue(table.staticTexts[value].firstMatch.exists, value)
                }
                app.scrollViews["Portfolio content"].scroll(byDeltaX: 0, deltaY: -500)
                capture(app, name: "Mixed holdings - \(appearance)")
                table.staticTexts["Sample Growth Fund"].click()
                app.typeKey(.return, modifierFlags: [])
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts["Mutual Fund Details"].waitForExistence(timeout: 5))
                for value in ["Kite mutual fund holdings", "12.345678901", "2.125", "42.123456789", "43.987654321", "2026-11-03", "TEST-FUND", "FOLIO-1"] {
                    XCTAssertTrue(sheet.staticTexts[value].firstMatch.exists, value)
                }
                XCTAssertFalse(sheet.staticTexts["999999"].exists)
                capture(app, name: "Mutual fund inspection - \(appearance)")
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
                table.staticTexts["Older NAV Fund"].click()
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(sheet.staticTexts["Mutual Fund Details"].waitForExistence(timeout: 5))
                for value in ["2026-11-02", "Acquisition cost unavailable", "Reported acquisition price", "0", "Unavailable"] {
                    XCTAssertTrue(sheet.staticTexts[value].firstMatch.exists, value)
                }
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                table.staticTexts["Undated Fund"].click()
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(sheet.staticTexts["Mutual Fund Details"].waitForExistence(timeout: 5))
                for value in ["NAV date unavailable", "NAV unavailable", "Reported NAV", "0"] {
                    XCTAssertTrue(sheet.staticTexts[value].firstMatch.exists, value)
                }
                capture(app, name: "Unavailable NAV and date - \(appearance)")
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            }
        }
    }

    /// Credential-free source rows with distinct NAV dates and an unusable acquisition price.
    func mutualFundFixture(name: String = "Sample Growth Fund") -> String {
        """
        {"retrievedAt":815000001,"holdings":[
          {"id":"mf-0","fund":"\(name)","symbol":"TEST-FUND","folio":"FOLIO-1","quantity":12.345678901,
           "averagePrice":42.123456789,"lastPrice":43.987654321,"navDate":"2026-11-03","pledgedQuantity":2.125,
           "limitations":["pledgeRelationshipUnknown"]},
          {"id":"mf-1","fund":"Older NAV Fund","symbol":"OLDER-FUND","quantity":0.125,
           "averagePrice":0,"lastPrice":12.5,"navDate":"2026-11-02","limitations":["acquisitionPriceUnavailable"]},
          {"id":"mf-2","fund":"Undated Fund","symbol":"UNDATED-FUND","quantity":1.001,
           "averagePrice":10,"lastPrice":0,"limitations":["navDateUnavailable","navUnavailable"]}
        ]}
        """
    }
#endif
