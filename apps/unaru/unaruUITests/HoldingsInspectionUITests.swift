//
//  HoldingsInspectionUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import XCTest

    @MainActor
    extension unaruUITests {
        func testHoldingsInspectionPreservesSourceIdentityMetadataAndAuthoritativeAllocation() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: inspectionSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200,
                            body: performanceFundsFixture().replacingOccurrences(of: "815000000", with: "815551000").replacingOccurrences(of: "\"id\":\"mf-0\"", with: "\"id\":\"0\""))
            backend.respond(path: "/portfolio/performance", status: 200,
                            body: allocationFixture().replacingOccurrences(of: "\"sourceRowID\":\"mf-0\"", with: "\"sourceRowID\":\"0\""))
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Allocation by Current Value"].waitForExistence(timeout: 10))
            app.staticTexts["Holdings"].firstMatch.click()
            let table = app.outlines["Holdings"]
            XCTAssertTrue(table.staticTexts["Inspection Security"].waitForExistence(timeout: 5))
            table.staticTexts["Inspection Security"].click()
            app.typeKey(.return, modifierFlags: [])
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.staticTexts["Holding Details"].waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.staticTexts["Inspection source retrieval time"].exists)
            XCTAssertEqual(sheet.staticTexts["Holding valuation date"].value as? String, "2026-11-04")
            XCTAssertTrue(sheet.staticTexts["Inspection Security"].exists)
            XCTAssertTrue(sheet.staticTexts["Kite securities holdings"].exists)
            XCTAssertTrue((sheet.staticTexts["Holding current value"].value as? String ?? "").contains("1,200.00"))
            XCTAssertEqual(sheet.staticTexts["Holding allocation"].value as? String, "60.00%")
            XCTAssertFalse(sheet.buttons["Buy"].exists)
            XCTAssertFalse(sheet.buttons["Sell"].exists)
            capture(app, name: "Security source retrieval and valuation date")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            table.staticTexts["Fractional Fund"].click()
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(sheet.staticTexts["Mutual Fund Details"].waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.staticTexts["Inspection source retrieval time"].exists)
            XCTAssertTrue(sheet.staticTexts["Kite mutual fund holdings"].exists)
            XCTAssertTrue(sheet.staticTexts["2.5"].exists)
            XCTAssertTrue(sheet.staticTexts["2026-11-03"].exists)
            XCTAssertTrue((sheet.staticTexts["Holding current value"].value as? String ?? "").contains("200.00"))
            XCTAssertEqual(sheet.staticTexts["Holding allocation"].value as? String, "10.00%")
            capture(app, name: "Fund with colliding source-local row identity")
            app.typeKey(.escape, modifierFlags: [])
        }

        func testHoldingsRefreshRetainsSearchAndCannotReattachInspectionToReusedRow() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: inspectionSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
            backend.respond(path: "/portfolio/performance", status: 200, body: allocationFixture())
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Allocation by Current Value"].waitForExistence(timeout: 10))
            app.staticTexts["Holdings"].firstMatch.click()
            let search = app.textFields["Search holdings by name or symbol"]
            search.click()
            replaceHoldingSearch(search, with: "inspection")
            let table = app.outlines["Holdings"]
            table.staticTexts["Inspection Security"].click()
            app.typeKey(.return, modifierFlags: [])
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.staticTexts["Holding Details"].waitForExistence(timeout: 5))
            let retrieval = sheet.staticTexts["Inspection source retrieval time"]
            let originalTime = retrieval.value as? String ?? retrieval.label
            backend.respond(path: "/portfolio/holdings", status: 503, hold: true, body: #"{"code":"portfolioUnavailable"}"#)
            app.typeKey("r", modifierFlags: .command)
            waitForPending(backend, path: "/portfolio/holdings")
            XCTAssertTrue(sheet.staticTexts["Showing the previous retrieval while refreshing."].waitForExistence(timeout: 5))
            backend.releaseResponses(path: "/portfolio/holdings")
            XCTAssertTrue(sheet.staticTexts["Stale data — showing the previous retrieval."].waitForExistence(timeout: 5))
            XCTAssertEqual(retrieval.value as? String ?? retrieval.label, originalTime)
            XCTAssertEqual(sheet.staticTexts["Holding allocation"].value as? String, "Unavailable")
            backend.respond(path: "/portfolio/holdings", status: 200, body: replacementInspectionFixture())
            backend.respond(path: "/portfolio/performance", status: 503, body: #"{"code":"portfolioUnavailable"}"#)
            sheet.buttons["Retry Securities"].click()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            XCTAssertEqual(search.value as? String, "inspection")
            XCTAssertTrue(app.staticTexts["No Matching Holdings"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Inspect Holding"].isEnabled)
            search.click()
            replaceHoldingSearch(search, with: "replacement")
            table.staticTexts["Replacement Security"].click()
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(sheet.staticTexts["Holding Details"].waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.staticTexts["Replacement Security"].exists)
            XCTAssertFalse(sheet.staticTexts["Inspection Security"].exists)
            XCTAssertTrue((sheet.staticTexts["Holding current value"].value as? String ?? "").contains("2,400.00"))
            let newRetrieval = sheet.staticTexts["Inspection source retrieval time"]
            XCTAssertNotEqual(newRetrieval.value as? String ?? newRetrieval.label, originalTime)
            XCTAssertFalse(sheet.staticTexts["Stale data — showing the previous retrieval."].exists)
            capture(app, name: "Reused source row ID opens only the replacement snapshot")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertEqual(backend.browserHandoffs, 1)
        }
    }

    /// Existing optional contract fields remain faithful when a helper supplies them.
    func inspectionSecuritiesFixture() -> String {
        var source = try! JSONSerialization.jsonObject(with: Data(performanceSecuritiesFixture().utf8)) as! [String: Any]
        var rows = source["holdings"] as! [[String: Any]]
        rows[0]["name"] = "Inspection Security"
        rows[0]["limitations"] = ["classificationUnavailable"]
        source["holdings"] = rows
        source["retrievedAt"] = 815_551_000
        source["valuationDate"] = "2026-11-04"
        return String(decoding: try! JSONSerialization.data(withJSONObject: source), as: UTF8.self)
    }

    /// A new retrieval reuses a source-local row ID for a different record and explicit authoritative values.
    func replacementInspectionFixture() -> String {
        var source = try! JSONSerialization.jsonObject(with: Data(inspectionSecuritiesFixture().utf8)) as! [String: Any]
        var rows = source["holdings"] as! [[String: Any]]
        rows[0]["name"] = "Replacement Security"
        rows[0]["quantity"] = 20
        rows[0]["performance"] = ["quantity": 20, "investedCost": 2000, "currentValue": 2400, "gain": 400, "returnPercent": 20, "excludedMTFOnly": false]
        source["holdings"] = rows
        source["readID"] = "replacement-read"
        source["retrievedAt"] = 815_551_100
        return String(decoding: try! JSONSerialization.data(withJSONObject: source), as: UTF8.self)
    }

#endif
