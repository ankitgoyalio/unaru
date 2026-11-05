//
//  HoldingsSortUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import XCTest

    @MainActor
    extension unaruUITests {
        func testHoldingsSortsAuthoritativeMeasuresAndKeepsUnavailableAfterZero() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: sortableSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
            app.buttons["View Holdings"].click()
            let table = app.outlines["Holdings"]
            XCTAssertTrue(table.staticTexts["Unpriced"].waitForExistence(timeout: 5))
            assertHoldingOrder(table, ["STOCK", "Transferred Fund", "Flat", "Loss", "Fractional Fund", "Unpriced"])
            let measure = app.popUpButtons["Sort By"]
            let direction = app.popUpButtons["Sort Direction"]
            XCTAssertEqual(measure.value as? String, "Current Value")
            XCTAssertEqual(direction.value as? String, "Descending")
            direction.click()
            app.menuItems["Ascending"].click()
            assertHoldingOrder(table, ["Fractional Fund", "Loss", "Flat", "Transferred Fund", "STOCK", "Unpriced"])
            measure.click()
            app.menuItems["Invested Cost"].click()
            assertHoldingOrder(table, ["Fractional Fund", "Unpriced", "Flat", "Loss", "STOCK", "Transferred Fund"])
            direction.click()
            app.menuItems["Descending"].click()
            assertHoldingOrder(table, ["STOCK", "Loss", "Flat", "Unpriced", "Fractional Fund", "Transferred Fund"])
            measure.click()
            app.menuItems["Return"].click()
            assertHoldingOrder(table, ["Fractional Fund", "STOCK", "Flat", "Loss", "Transferred Fund", "Unpriced"])
            XCTAssertTrue(table.staticTexts["0.00%"].exists)
            XCTAssertTrue(table.staticTexts["-50.00%"].exists)
            XCTAssertTrue(table.staticTexts["Unavailable"].firstMatch.exists)
            direction.click()
            app.menuItems["Ascending"].click()
            assertHoldingOrder(table, ["Loss", "Flat", "STOCK", "Fractional Fund", "Transferred Fund", "Unpriced"])
            XCTAssertTrue(app.staticTexts["Unavailable values sort last in either direction. Return uses unrealised return percentage."].exists)
            capture(app, name: "Mixed holdings sorted by return")
        }

        /// Checks the visible user-facing order rather than an internal sorter or view model.
        private func assertHoldingOrder(_ table: XCUIElement, _ names: [String], file: StaticString = #filePath, line: UInt = #line) {
            for (first, second) in zip(names, names.dropFirst()) {
                let firstRow = table.staticTexts[first].firstMatch
                let secondRow = table.staticTexts[second].firstMatch
                XCTAssertTrue(firstRow.exists, first, file: file, line: line)
                XCTAssertTrue(secondRow.exists, second, file: file, line: line)
                XCTAssertLessThan(firstRow.frame.minY, secondRow.frame.minY, "\(first) before \(second)", file: file, line: line)
            }
        }
    }

    /// Explicit backend values include zero gain, a loss and missing price, independent of UI calculations.
    func sortableSecuritiesFixture() -> String {
        var source = try! JSONSerialization.jsonObject(with: Data(performanceSecuritiesFixture().utf8)) as! [String: Any]
        var rows = source["holdings"] as! [[String: Any]]
        var flat = rows[0]
        flat["id"] = "1"
        flat["symbol"] = "Flat"
        flat["isin"] = "FLAT"
        flat["quantity"] = 5
        flat["lastPrice"] = 100
        flat["performance"] = ["quantity": 5, "investedCost": 500, "currentValue": 500, "gain": 0, "returnPercent": 0, "excludedMTFOnly": false]
        var unpriced = flat
        unpriced["id"] = "2"
        unpriced["symbol"] = "Unpriced"
        unpriced["isin"] = "UNPRICED"
        unpriced["quantity"] = 10
        unpriced["averagePrice"] = 20
        unpriced["lastPrice"] = 0
        unpriced["limitations"] = ["marketPriceUnavailable", "valuationDateUnavailable", "classificationUnavailable", "nameUnavailable"]
        unpriced["performance"] = ["quantity": 10, "investedCost": 200, "excludedMTFOnly": false]
        var loss = flat
        loss["id"] = "3"
        loss["symbol"] = "Loss"
        loss["isin"] = "LOSS"
        loss["quantity"] = 8
        loss["lastPrice"] = 50
        loss["performance"] = ["quantity": 8, "investedCost": 800, "currentValue": 400, "gain": -400, "returnPercent": -50, "excludedMTFOnly": false]
        rows += [flat, unpriced, loss]
        source["holdings"] = rows
        return String(decoding: try! JSONSerialization.data(withJSONObject: source), as: UTF8.self)
    }
#endif
