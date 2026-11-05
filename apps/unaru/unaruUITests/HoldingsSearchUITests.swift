//
//  HoldingsSearchUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import XCTest

    @MainActor
    extension unaruUITests {
        func testHoldingsSearchesNamesAndSymbolsAcrossBothSources() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
            backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture().replacingOccurrences(of: "\"symbol\":\"FUND\"", with: "\"symbol\":\"UNIQUE-ISIN\""))
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
            app.buttons["View Holdings"].click()
            let search = app.textFields["Search holdings by name or symbol"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            let table = app.outlines["Holdings"]
            XCTAssertTrue(table.staticTexts["STOCK"].waitForExistence(timeout: 5))
            XCTAssertTrue(table.staticTexts["Fractional Fund"].exists)
            search.click()
            replaceHoldingSearch(search, with: "fractional")
            XCTAssertTrue(table.staticTexts["Fractional Fund"].exists)
            XCTAssertFalse(table.staticTexts["STOCK"].exists)
            replaceHoldingSearch(search, with: "unique-isin")
            XCTAssertTrue(table.staticTexts["Fractional Fund"].exists)
            XCTAssertFalse(table.staticTexts["Transferred Fund"].exists)
            replaceHoldingSearch(search, with: "stock")
            XCTAssertTrue(table.staticTexts["STOCK"].exists)
            XCTAssertFalse(table.staticTexts["Fractional Fund"].exists)
            replaceHoldingSearch(search, with: "zz")
            XCTAssertTrue(app.staticTexts["No Matching Holdings"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["No Holdings"].exists)
            app.buttons["Clear Search and Filters"].click()
            XCTAssertTrue(table.staticTexts["STOCK"].waitForExistence(timeout: 5))
            XCTAssertTrue(table.staticTexts["Fractional Fund"].exists)
            XCTAssertTrue(app.buttons["Open Kite account"].exists)
        }

        func testHoldingsFiltersSupportedTypesAndRetainsUnknownInBothAppearances() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: performanceSecuritiesFixture())
                backend.respond(path: "/portfolio/mutual-funds", status: 200, body: performanceFundsFixture())
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.buttons["View Holdings"].waitForExistence(timeout: 10))
                app.buttons["View Holdings"].click()
                let filter = app.popUpButtons["Investment Type"]
                XCTAssertTrue(filter.waitForExistence(timeout: 5))
                filter.click()
                app.menuItems["Mutual Funds"].click()
                let table = app.outlines["Holdings"]
                XCTAssertTrue(table.staticTexts["Fractional Fund"].exists)
                XCTAssertFalse(table.staticTexts["STOCK"].exists)
                filter.click()
                app.menuItems["Unknown"].click()
                XCTAssertTrue(table.staticTexts["STOCK"].exists)
                XCTAssertFalse(table.staticTexts["Fractional Fund"].exists)
                let search = app.textFields["Search holdings by name or symbol"]
                search.click()
                replaceHoldingSearch(search, with: "fund")
                XCTAssertTrue(app.staticTexts["No Matching Holdings"].waitForExistence(timeout: 5))
                app.buttons["Clear Search and Filters"].click()
                XCTAssertTrue(table.staticTexts["STOCK"].waitForExistence(timeout: 5))
                XCTAssertTrue(table.staticTexts["Fractional Fund"].exists)
                XCTAssertEqual(app.windows.firstMatch.frame.width, 1024, accuracy: 1)
                XCTAssertEqual(app.windows.firstMatch.frame.height, 846, accuracy: 1)
                capture(app, name: "Holdings search and type controls - \(appearance)")
            }
        }

        /// Explicit unmodified key events avoid the host keyboard layout synthesizing menu equivalents.
        func replaceHoldingSearch(_ field: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
            for _ in 0 ..< (field.value as? String ?? "").count {
                field.typeKey(.delete, modifierFlags: [])
            }
            for character in text {
                field.typeKey(String(character), modifierFlags: [])
            }
            XCTAssertEqual(field.value as? String, text, file: file, line: line)
        }
    }
#endif
