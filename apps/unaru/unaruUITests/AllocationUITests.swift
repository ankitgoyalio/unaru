//
//  AllocationUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import XCTest

    @MainActor
    extension unaruUITests {
        func testAllocationShowsRankedHoldingsSupportedGroupsAndCoverageInBothAppearances() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
                backend.respond(path: "/portfolio/performance", status: 200, body: allocationFixture())
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Allocation by Current Value"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["Allocation coverage: 3 of 3 holdings"].exists)
                let first = app.descendants(matching: .any)["Allocation holding 1"].firstMatch
                XCTAssertTrue(first.label.contains("1. STOCK"))
                XCTAssertTrue(first.label.contains("60.00%"))
                XCTAssertTrue(app.descendants(matching: .any)["Allocation holding 2"].firstMatch.label.contains("2. Transferred Fund"))
                XCTAssertTrue(app.descendants(matching: .any)["Allocation holding 3"].firstMatch.label.contains("3. Fractional Fund"))
                let unknown = app.descendants(matching: .any)["Allocation group unknown"].firstMatch
                XCTAssertTrue(unknown.label.contains("Unknown investment type"))
                XCTAssertTrue(unknown.label.contains("60.00%"))
                let funds = app.descendants(matching: .any)["Allocation group mutualFund"].firstMatch
                XCTAssertTrue(funds.label.contains("Mutual funds"))
                XCTAssertTrue(funds.label.contains("40.00%"))
                XCTAssertTrue(app.staticTexts["Security types and ETF underlying exposure are not supplied by these holdings sources."].exists)
                XCTAssertEqual(app.windows.firstMatch.frame.width, 1024, accuracy: 1)
                XCTAssertEqual(app.windows.firstMatch.frame.height, 846, accuracy: 1)
                app.scrollViews["Portfolio content"].firstMatch.scroll(byDeltaX: 0, deltaY: -450)
                XCTAssertTrue(first.isHittable)
                capture(app, name: "Current-value allocation - \(appearance)")
                app.buttons["View Holdings"].click()
                app.outlines["Securities holdings"].staticTexts["STOCK"].click()
                app.typeKey(.return, modifierFlags: [])
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts["Holding allocation"].waitForExistence(timeout: 5))
                XCTAssertEqual(sheet.staticTexts["Holding allocation"].value as? String, "60.00%")
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                let fundsTable = app.outlines["Mutual fund holdings"]
                fundsTable.staticTexts["Transferred Fund"].click()
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(sheet.staticTexts["Mutual Fund Details"].waitForExistence(timeout: 5))
                XCTAssertEqual(sheet.staticTexts["Holding allocation"].value as? String, "30.00%")
                XCTAssertEqual(sheet.staticTexts["Holding invested cost"].value as? String, "Unavailable")
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
            }
        }
    }

    /// Explicit authoritative values at the HTTP seam, independent of the implementation's formulas.
    func allocationFixture() -> String {
        var result = try! JSONSerialization.jsonObject(with: Data(performanceFixture().utf8)) as! [String: Any]
        result["rows"] = [
            ["source": "securities", "sourceRowID": "0", "overlapsSources": false, "allocationPercent": 60,
             "values": ["quantity": 10, "investedCost": 1000, "currentValue": 1200, "gain": 200, "returnPercent": 20, "excludedMTFOnly": false]],
            ["source": "mutualFunds", "sourceRowID": "mf-0", "overlapsSources": false, "allocationPercent": 10,
             "values": ["quantity": 2.5, "investedCost": 100, "currentValue": 200, "gain": 100, "returnPercent": 100, "excludedMTFOnly": false]],
            ["source": "mutualFunds", "sourceRowID": "mf-1", "overlapsSources": false, "allocationPercent": 30,
             "values": ["quantity": 10, "currentValue": 600, "excludedMTFOnly": false]],
        ]
        result["allocation"] = [
            "currentValue": 2000, "totalHoldings": 3, "valuedHoldings": 3, "excludedMTFHoldings": 0,
            "largestHoldings": [
                ["source": "securities", "sourceRowID": "0", "name": "STOCK", "investmentType": "unknown", "currentValue": 1200, "allocationPercent": 60],
                ["source": "mutualFunds", "sourceRowID": "mf-1", "name": "Transferred Fund", "investmentType": "mutualFund", "currentValue": 600, "allocationPercent": 30],
                ["source": "mutualFunds", "sourceRowID": "mf-0", "name": "Fractional Fund", "investmentType": "mutualFund", "currentValue": 200, "allocationPercent": 10],
            ],
            "groups": [
                ["investmentType": "unknown", "currentValue": 1200, "allocationPercent": 60, "totalHoldings": 1, "valuedHoldings": 1],
                ["investmentType": "mutualFund", "currentValue": 800, "allocationPercent": 40, "totalHoldings": 2, "valuedHoldings": 2],
            ],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: result), as: UTF8.self)
    }
#endif
