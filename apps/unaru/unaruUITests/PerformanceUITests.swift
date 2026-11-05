//
//  PerformanceUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import XCTest

    @MainActor
    extension unaruUITests {
        func testPerformanceOverviewAndRowsShowAuthoritativeValuesAndCoverage() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
                backend.respond(path: "/portfolio/performance", status: 200, body: performanceFixture())
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Current-Holdings Unrealised Performance"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["Performance current value"].waitForExistence(timeout: 10))
                XCTAssertTrue((app.staticTexts["Performance current value"].value as? String ?? app.staticTexts["Performance current value"].label).contains("2,000.00"))
                XCTAssertTrue((app.staticTexts["Performance invested cost"].value as? String ?? app.staticTexts["Performance invested cost"].label).contains("1,100.00"))
                XCTAssertTrue((app.staticTexts["Performance gain"].value as? String ?? app.staticTexts["Performance gain"].label).contains("300.00"))
                XCTAssertTrue((app.staticTexts["Performance return"].value as? String ?? app.staticTexts["Performance return"].label).contains("27.27%"))
                XCTAssertTrue(app.staticTexts["Value coverage: 3 of 3 holdings"].exists)
                XCTAssertTrue(app.staticTexts["Return coverage: 2 of 3 holdings"].exists)
                XCTAssertTrue((app.staticTexts["Performance matched cost"].value as? String ?? app.staticTexts["Performance matched cost"].label).contains("1,100.00"))
                capture(app, name: "Performance overview - \(appearance)")
                app.buttons["View Holdings"].click()
                let securities = app.outlines["Holdings"]
                XCTAssertTrue(securities.waitForExistence(timeout: 5))
                XCTAssertTrue(securities.staticTexts.containing(NSPredicate(format: "label CONTAINS '1,200.00' OR value CONTAINS '1,200.00'")).firstMatch.exists)
                XCTAssertTrue(securities.staticTexts["20.00%"].exists)
                capture(app, name: "Performance holdings - \(appearance)")
                securities.staticTexts["STOCK"].click()
                app.typeKey(.return, modifierFlags: [])
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts["Holding Details"].waitForExistence(timeout: 5))
                XCTAssertTrue((sheet.staticTexts["Holding current value"].value as? String ?? sheet.staticTexts["Holding current value"].label).contains("1,200.00"))
                XCTAssertTrue((sheet.staticTexts["Holding gain"].value as? String ?? sheet.staticTexts["Holding gain"].label).contains("200.00"))
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
            }
        }

        func testPerformanceCrossSourceOverlapWithholdsRowValues() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture().replacingOccurrences(of: "FUND\"", with: "TEST-ISIN\""))
            var total = try JSONSerialization.jsonObject(with: Data(performanceFixture().utf8)) as! [String: Any]
            total["investedCost"] = nil
            total["currentValue"] = 600
            total["gain"] = nil
            total["returnPercent"] = nil
            total["matchedCost"] = nil
            total["matchedValue"] = nil
            total["costCount"] = 0
            total["valueCount"] = 1
            total["returnCount"] = 0
            total["rows"] = [
                ["source": "securities", "sourceRowID": "0", "values": ["excludedMTFOnly": false], "overlapsSources": true],
                ["source": "mutualFunds", "sourceRowID": "mf-0", "values": ["excludedMTFOnly": false], "overlapsSources": true],
            ]
            try backend.respond(path: "/portfolio/performance", status: 200, hold: true, body: String(decoding: JSONSerialization.data(withJSONObject: total), as: UTF8.self))
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            waitForPending(backend)
            app.buttons["View Holdings"].click()
            let table = app.outlines["Holdings"]
            XCTAssertTrue(table.staticTexts["STOCK"].waitForExistence(timeout: 5))
            table.staticTexts["STOCK"].click()
            app.typeKey(.return, modifierFlags: [])
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.staticTexts["Holding current value"].waitForExistence(timeout: 5))
            XCTAssertTrue((sheet.staticTexts["Holding current value"].value as? String ?? "").contains("1,200.00"))
            backend.releaseResponses()
            XCTAssertTrue(sheet.staticTexts["Potential overlap across holdings sources — calculated contribution unavailable."].waitForExistence(timeout: 5))
            XCTAssertEqual(sheet.staticTexts["Holding current value"].value as? String, "Unavailable")
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    /// Independently specified backend-calculated values; UI fixtures never implement the formulas.
    func performanceSecuritiesFixture() -> String {
        var source = try! JSONSerialization.jsonObject(with: Data(portfolioFixture().utf8)) as! [String: Any]
        var rows = source["holdings"] as! [[String: Any]]
        rows[0]["quantity"] = 10
        rows[0]["t1Quantity"] = 0
        rows[0]["collateralQuantity"] = 0
        rows[0]["averagePrice"] = 100
        rows[0]["lastPrice"] = 120
        rows[0]["mtf"] = nil
        rows[0]["limitations"] = ["nameUnavailable", "classificationUnavailable", "valuationDateUnavailable"]
        rows[0]["performance"] = ["quantity": 10, "investedCost": 1000, "currentValue": 1200, "gain": 200, "returnPercent": 20, "excludedMTFOnly": false]
        source["holdings"] = rows
        source["readID"] = "securities-read"
        return String(decoding: try! JSONSerialization.data(withJSONObject: source), as: UTF8.self)
    }

    func performanceFundsFixture() -> String {
        #"{"readID":"funds-read","retrievedAt":815000000,"holdings":[{"id":"mf-0","fund":"Fractional Fund","symbol":"FUND","quantity":2.5,"averagePrice":40,"lastPrice":80,"navDate":"2026-11-03","limitations":[],"performance":{"quantity":2.5,"investedCost":100,"currentValue":200,"gain":100,"returnPercent":100,"excludedMTFOnly":false}},{"id":"mf-1","fund":"Transferred Fund","symbol":"TRANSFER","quantity":10,"averagePrice":0,"lastPrice":60,"limitations":["acquisitionPriceUnavailable","navDateUnavailable"],"performance":{"quantity":10,"currentValue":600,"excludedMTFOnly":false}}]}"#
    }

    func performanceFixture(value: Int = 2000) -> String {
        """
        {"sources":{"securitiesReadID":"securities-read","mutualFundsReadID":"funds-read"},
        "investedCost":1100,"currentValue":\(value),"gain":300,"returnPercent":27.27272727272727,
        "matchedCost":1100,"matchedValue":1400,"totalHoldings":3,"costCount":2,"valueCount":3,"returnCount":2,"excludedMTFCount":0}
        """
    }
#endif
