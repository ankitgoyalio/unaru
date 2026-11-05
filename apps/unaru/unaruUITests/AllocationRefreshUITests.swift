//
//  AllocationRefreshUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import XCTest

    @MainActor
    extension unaruUITests {
        func testAllocationRefreshUpdatesRankingAndWithholdsStaleInspectionWeights() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
            backend.respond(path: "/portfolio/performance", status: 200, body: allocationFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Allocation by Current Value"].waitForExistence(timeout: 10))
            backend.respond(path: "/portfolio/holdings", status: 200, body: refreshedAllocationSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture().replacingOccurrences(of: "\"lastPrice\":60", with: "\"lastPrice\":180").replacingOccurrences(of: "\"currentValue\":600", with: "\"currentValue\":1800"))
            backend.respond(path: "/portfolio/performance", status: 200, hold: true, body: refreshedAllocationFixture())
            app.typeKey("r", modifierFlags: .command)
            waitForPending(backend)
            XCTAssertFalse(app.staticTexts["Allocation by Current Value"].exists)
            backend.respond(path: "/portfolio/performance", status: 200, body: refreshedAllocationFixture())
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["Allocation coverage: 3 of 4 holdings"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Incomplete allocation — percentages cover only valued holdings."].exists)
            XCTAssertTrue(app.staticTexts["Holdings with excluded MTF components: 1"].exists)
            let first = app.descendants(matching: .any)["Allocation holding 1"].firstMatch
            XCTAssertTrue(first.label.contains("1. Transferred Fund"))
            XCTAssertTrue(first.label.contains("56.25%"))
            XCTAssertTrue(app.descendants(matching: .any)["Allocation holding 2"].firstMatch.label.contains("2. STOCK"))
            XCTAssertTrue(app.descendants(matching: .any)["Allocation group unknown"].firstMatch.label.contains("Valued: 1 of 2 holdings"))
            XCTAssertTrue(app.descendants(matching: .any)["Allocation group mutualFund"].firstMatch.label.contains("62.50%"))
            backend.respond(path: "/portfolio/holdings", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["Couldn’t refresh securities holdings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Allocation by Current Value"].exists)
            app.staticTexts["Holdings"].firstMatch.click()
            let table = app.outlines["Holdings"]
            XCTAssertTrue(table.waitForExistence(timeout: 5))
            table.staticTexts["STOCK"].click()
            app.typeKey(.return, modifierFlags: [])
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.staticTexts["Holding allocation"].waitForExistence(timeout: 5))
            XCTAssertEqual(sheet.staticTexts["Holding allocation"].value as? String, "Unavailable")
            XCTAssertTrue((sheet.staticTexts["Holding current value"].value as? String ?? "").contains("1,200.00"))
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testAllocationDistinguishesEmptyInventoryAndUnavailableValuations() throws {
            for empty in [true, false] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: unavailableAllocationSource(performanceSecuritiesFixture(), empty: empty))
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: unavailableAllocationSource(performanceFundsFixture(), empty: empty))
                backend.respond(path: "/portfolio/performance", status: 200, body: unavailableAllocationFixture(empty: empty))
                let app = launch(backend: backend)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Allocation by Current Value"].waitForExistence(timeout: 10))
                if empty {
                    XCTAssertTrue(app.staticTexts["No ordinary holdings to allocate."].exists)
                    XCTAssertTrue(app.staticTexts["Allocation coverage: 0 of 0 holdings"].exists)
                } else {
                    XCTAssertTrue(app.staticTexts["Allocation unavailable — no positive valued total."].exists)
                    XCTAssertTrue(app.staticTexts["Allocation coverage: 0 of 3 holdings"].exists)
                    XCTAssertTrue(app.descendants(matching: .any)["Allocation group unknown"].firstMatch.label.contains("Unavailable"))
                }
                XCTAssertFalse(app.descendants(matching: .any)["Allocation holding 1"].firstMatch.exists)
            }
        }
    }

    /// A second explicit authoritative result changes rank, groups, financing omissions and valuation coverage.
    func refreshedAllocationFixture() -> String {
        var result = try! JSONSerialization.jsonObject(with: Data(allocationFixture().utf8)) as! [String: Any]
        result["currentValue"] = 3200
        result["totalHoldings"] = 4
        var rows = result["rows"] as! [[String: Any]]
        rows[0]["allocationPercent"] = 37.5
        rows[1]["allocationPercent"] = 6.25
        rows[2]["allocationPercent"] = 56.25
        rows[2]["values"] = ["quantity": 10, "currentValue": 1800, "excludedMTFOnly": false]
        rows.append(["source": "securities", "sourceRowID": "1", "overlapsSources": false, "values": ["excludedMTFOnly": false]])
        result["rows"] = rows
        result["allocation"] = [
            "currentValue": 3200, "totalHoldings": 4, "valuedHoldings": 3, "excludedMTFHoldings": 1,
            "largestHoldings": [
                ["source": "mutualFunds", "sourceRowID": "mf-1", "name": "Transferred Fund", "investmentType": "mutualFund", "currentValue": 1800, "allocationPercent": 56.25],
                ["source": "securities", "sourceRowID": "0", "name": "STOCK", "investmentType": "unknown", "currentValue": 1200, "allocationPercent": 37.5],
                ["source": "mutualFunds", "sourceRowID": "mf-0", "name": "Fractional Fund", "investmentType": "mutualFund", "currentValue": 200, "allocationPercent": 6.25],
            ],
            "groups": [
                ["investmentType": "unknown", "currentValue": 1200, "allocationPercent": 37.5, "totalHoldings": 2, "valuedHoldings": 1],
                ["investmentType": "mutualFund", "currentValue": 2000, "allocationPercent": 62.5, "totalHoldings": 2, "valuedHoldings": 2],
            ],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: result), as: UTF8.self)
    }

    /// Successful empty inventory and a nonempty unavailable inventory are distinct HTTP results.
    func unavailableAllocationFixture(empty: Bool) -> String {
        var result = try! JSONSerialization.jsonObject(with: Data(allocationFixture().utf8)) as! [String: Any]
        for key in ["investedCost", "currentValue", "gain", "matchedCost", "matchedValue"] {
            result[key] = empty ? 0 : NSNull()
        }
        result["returnPercent"] = nil
        result["totalHoldings"] = empty ? 0 : 3
        for key in ["costCount", "valueCount", "returnCount"] {
            result[key] = 0
        }
        result["rows"] = []
        result["allocation"] = [
            "currentValue": empty ? 0 : NSNull(), "totalHoldings": empty ? 0 : 3, "valuedHoldings": 0, "excludedMTFHoldings": 0,
            "largestHoldings": [],
            "groups": empty ? [] : [["investmentType": "unknown", "totalHoldings": 1, "valuedHoldings": 0],
                                    ["investmentType": "mutualFund", "totalHoldings": 2, "valuedHoldings": 0]],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: result), as: UTF8.self)
    }

    /// Retains an unknown security with unavailable value, alongside separately financed inventory.
    func refreshedAllocationSecuritiesFixture() -> String {
        var source = try! JSONSerialization.jsonObject(with: Data(performanceSecuritiesFixture().utf8)) as! [String: Any]
        var rows = source["holdings"] as! [[String: Any]]
        rows[0]["mtf"] = ["quantity": 10, "usedQuantity": 0, "averagePrice": 50, "value": 1000, "initialMargin": 100]
        var missing = rows[0]
        missing["id"] = "1"
        missing["symbol"] = "NO-PRICE"
        missing["isin"] = "NO-PRICE"
        missing["mtf"] = nil
        missing["averagePrice"] = 0
        missing["lastPrice"] = 0
        missing["performance"] = ["quantity": 10, "excludedMTFOnly": false]
        rows.append(missing)
        source["holdings"] = rows
        return String(decoding: try! JSONSerialization.data(withJSONObject: source), as: UTF8.self)
    }

    /// Source snapshots agree with the empty or unvalued analysis, without doing financial arithmetic.
    func unavailableAllocationSource(_ fixture: String, empty: Bool) -> String {
        var source = try! JSONSerialization.jsonObject(with: Data(fixture.utf8)) as! [String: Any]
        var rows = source["holdings"] as! [[String: Any]]
        for index in rows.indices {
            rows[index]["lastPrice"] = 0
            rows[index]["averagePrice"] = 0
            rows[index]["performance"] = ["excludedMTFOnly": false]
        }
        source["holdings"] = empty ? [] : rows
        return String(decoding: try! JSONSerialization.data(withJSONObject: source), as: UTF8.self)
    }
#endif
