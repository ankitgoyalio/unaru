//
//  AccountSheetUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 03/11/2026.

#if os(macOS)
    import AppKit
    import XCTest

    @MainActor
    extension unaruUITests {
        func testOpeningAccountShowsKnownIdentityWhileRefreshingMissingDetails() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.useProfile(#"{"name":"Asha Rao","userID":"AB1234"}"#)
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            let account = app.buttons["Open Kite account"]
            XCTAssertTrue(account.waitForExistence(timeout: 10))
            backend.respond(path: "/profile", status: 200, hold: true,
                            body: #"{"name":"Asha Rao","userID":"AB1234","email":"updated@example.invalid"}"#)
            account.click()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.staticTexts["Asha Rao"].exists)
            XCTAssertTrue(sheet.staticTexts["AB1234"].exists)
            waitForPending(backend)
            XCTAssertTrue(sheet.activityIndicators["Refreshing account details"].waitForExistence(timeout: 5))
            XCTAssertFalse(sheet.staticTexts["Not available"].exists)
            backend.respond(path: "/profile", status: 200)
            backend.releaseResponses()
            XCTAssertTrue(sheet.staticTexts["updated@example.invalid"].waitForExistence(timeout: 10))
            XCTAssertFalse(sheet.activityIndicators["Refreshing account details"].exists)
            sheet.buttons["Done"].click()
            backend.useProfile(#"{"name":"Asha Rao","userID":"AB1234","email":"reopened@example.invalid"}"#)
            account.click()
            XCTAssertTrue(sheet.staticTexts["reopened@example.invalid"].waitForExistence(timeout: 10))
        }

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
                account.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).click()
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.waitForExistence(timeout: 5))
                XCTAssertTrue(sheet.staticTexts["Kite account"].exists)
                XCTAssertTrue(sheet.staticTexts["Account details"].exists)
                XCTAssertTrue(sheet.staticTexts["Trading permissions"].exists)
                XCTAssertTrue(sheet.buttons["Enlarge account avatar"].exists)
                XCTAssertTrue(sheet.staticTexts["asha@example.invalid"].exists)
                XCTAssertTrue(sheet.staticTexts["ZERODHA"].exists)
                XCTAssertTrue(sheet.staticTexts["individual"].exists)
                XCTAssertTrue(sheet.staticTexts["NSE, BSE"].exists)
                XCTAssertTrue(sheet.staticTexts["CNC, MIS"].exists)
                XCTAssertTrue(sheet.staticTexts["LIMIT, SL-M"].exists)
                sheet.buttons["Enlarge account avatar"].click()
                let avatar = app.popovers.firstMatch
                XCTAssertTrue(avatar.waitForExistence(timeout: 5))
                capture(app, name: "Enlarged avatar - \(appearance)")
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(avatar.waitForNonExistence(timeout: 5))
                XCTAssertTrue(sheet.exists)
                sheet.buttons["Log Out"].click()
                let confirmation = app.sheets["alert"]
                XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
                XCTAssertEqual(backend.logouts, 0)
                capture(app, name: "Confirm logout - \(appearance)")
                confirmation.buttons["Cancel"].click()
                XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
                XCTAssertTrue(sheet.exists)
                XCTAssertEqual(backend.logouts, 0)
                sheet.buttons["Log Out"].click()
                XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
                XCTAssertTrue(sheet.exists)
                XCTAssertEqual(backend.logouts, 0)
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
                let broker = sheet.staticTexts.matching(identifier: "ZERODHA").allElementsBoundByIndex.first(where: \.isEnabled)
                XCTAssertNotNil(broker)
                broker?.doubleClick()
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                account.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.5)).click()
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
            XCTAssertTrue(sheet.staticTexts["Not available"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(sheet.staticTexts.matching(identifier: "Not available").allElementsBoundByIndex.filter(\.isEnabled).count, 4)
            XCTAssertTrue(sheet.staticTexts["None enabled"].exists)
            XCTAssertTrue(sheet.staticTexts["LIMIT, SL-M"].exists)
            XCTAssertFalse(sheet.buttons["Copy email"].exists)
            XCTAssertTrue(sheet.buttons["Copy Kite ID"].exists)
        }
    }
#endif
