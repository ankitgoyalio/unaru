//
//  AccountSheetUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 02/11/2026.

#if os(macOS)
    import AppKit
    import XCTest

    @MainActor
    extension unaruUITests {
        func testAccountRowOpensSheetAndRestoresKeyboardFocus() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                let account = app.buttons["Open Kite account"]
                XCTAssertTrue(account.waitForExistence(timeout: 10))
                // Exercise both text and avatar within the single native button.
                account.staticTexts["Asha Rao"].click()
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.waitForExistence(timeout: 5))
                XCTAssertTrue(sheet.staticTexts["Kite account"].exists)
                XCTAssertTrue(sheet.staticTexts["Account details"].exists)
                XCTAssertTrue(sheet.staticTexts["Trading permissions"].exists)
                XCTAssertTrue(sheet.staticTexts["AR"].exists)
                XCTAssertTrue(sheet.staticTexts["asha@example.invalid"].exists)
                XCTAssertTrue(sheet.staticTexts["ZERODHA"].exists)
                XCTAssertTrue(sheet.staticTexts["individual"].exists)
                XCTAssertTrue(sheet.staticTexts["NSE, BSE"].exists)
                XCTAssertTrue(sheet.staticTexts["CNC, MIS"].exists)
                XCTAssertTrue(sheet.staticTexts["LIMIT, SL-M"].exists)
                sheet.buttons["Copy Kite ID"].click()
                XCTAssertEqual(NSPasteboard.general.string(forType: .string), "AB1234")
                XCTAssertTrue(sheet.staticTexts["Copied"].waitForExistence(timeout: 2))
                sheet.buttons["Copy email"].click()
                XCTAssertEqual(NSPasteboard.general.string(forType: .string), "asha@example.invalid")
                capture(app, name: "Kite account - \(appearance)")
                sheet.buttons["Done"].click()
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                app.typeKey(.space, modifierFlags: [])
                XCTAssertTrue(sheet.waitForExistence(timeout: 5))
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                account.staticTexts["AR"].click()
                XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            }
        }

        func testAccountSheetDistinguishesMissingAndEmptyDetails() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.useProfile(#"{"name":"Asha Rao","userID":"AB1234","email":"  ","broker":null,"products":[],"orderTypes":["LIMIT","SL-M"]}"#)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            let account = app.buttons["Open Kite account"]
            XCTAssertTrue(account.waitForExistence(timeout: 10))
            account.click()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            XCTAssertEqual(sheet.staticTexts.matching(identifier: "Not available").count, 4)
            XCTAssertTrue(sheet.staticTexts["None enabled"].exists)
            XCTAssertTrue(sheet.staticTexts["LIMIT, SL-M"].exists)
            XCTAssertFalse(sheet.buttons["Copy email"].exists)
            XCTAssertTrue(sheet.buttons["Copy Kite ID"].exists)
        }
    }
#endif
