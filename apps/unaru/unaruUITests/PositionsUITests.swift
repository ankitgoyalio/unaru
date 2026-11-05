//
//  PositionsUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import XCTest

#if os(macOS)
    @MainActor
    extension unaruUITests {
        func testPositionsGroupsNetExposureAndInspectsBrokerDetailsWithKeyboard() throws {
            for appearance in ["Light", "Dark"] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                backend.respond(path: "/portfolio/holdings", status: 200, body: portfolioFixture())
                backend.respond(path: "/portfolio/positions", status: 200, body: positionsFixture())
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Portfolio Overview"].waitForExistence(timeout: 10))
                let positions = app.staticTexts["Positions"].firstMatch
                guard positions.waitForExistence(timeout: 5) else {
                    XCTFail("Positions child must be available beneath Portfolio")
                    return
                }
                positions.click()
                XCTAssertTrue(app.staticTexts["Current Net Positions"].waitForExistence(timeout: 5))
                let current = app.outlines["Current net positions"]
                let closed = app.outlines["Closed positions"]
                XCTAssertTrue(current.staticTexts["SHORTFUT"].waitForExistence(timeout: 5))
                XCTAssertTrue(current.staticTexts["DELIVERY"].exists)
                XCTAssertFalse(current.staticTexts["CLOSED"].exists)
                XCTAssertTrue(closed.staticTexts["CLOSED"].exists)
                XCTAssertTrue(closed.staticTexts["Unavailable"].exists)
                XCTAssertTrue(current.staticTexts["-2"].exists)
                XCTAssertTrue(app.staticTexts["Positions retrieval time"].exists)
                XCTAssertTrue(app.staticTexts["Trading P&L is separate from holdings returns."].exists)
                current.staticTexts["SHORTFUT"].click()
                app.typeKey(.return, modifierFlags: [])
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.staticTexts["Position Details"].waitForExistence(timeout: 5))
                for label in ["MCX", "NRML", "Signed net quantity", "Multiplier", "1,000", "Realised trading P&L", "Unrealised trading P&L", "Price valuation date unavailable"] {
                    XCTAssertTrue(sheet.descendants(matching: .any)[label].firstMatch.exists, label)
                }
                capture(app, name: "Position details - \(appearance)")
                sheet.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
                XCTAssertTrue(sheet.descendants(matching: .any)["Day sell value"].firstMatch.isHittable)
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                closed.staticTexts["CLOSED"].click()
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(sheet.staticTexts["Position Details"].waitForExistence(timeout: 5))
                XCTAssertTrue(sheet.staticTexts["Closed"].exists)
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
                capture(app, name: "Current and closed positions - \(appearance)")
                XCTAssertEqual(app.windows.firstMatch.frame.width, 1024, accuracy: 1)
                XCTAssertEqual(app.windows.firstMatch.frame.height, 846, accuracy: 1)
                app.staticTexts["Holdings"].firstMatch.click()
                XCTAssertTrue(app.staticTexts["STOCK"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["DELIVERY"].exists)
                XCTAssertTrue(app.buttons["Open Kite account"].exists)
            }
        }
    }

    /// Credential-free app-facing rows, independent of the SDK fixture.
    func positionsFixture(symbol: String = "SHORTFUT") -> String {
        let fields = """
        "instrumentToken":53496327,"overnightQuantity":-1,
        "averagePrice":161.05123456789,"closePrice":162,"value":-322100,
        "pnl":1850,"m2m":1800,
        "buyQuantity":1,"buyPrice":160,"buyValue":160000,"buyM2M":159900,
        "sellQuantity":3,"sellPrice":161,"sellValue":483000,"sellM2M":482900,
        "dayBuyQuantity":1,"dayBuyPrice":160,"dayBuyValue":160000,
        "daySellQuantity":2,"daySellPrice":161,"daySellValue":322000
        """
        return """
        {"retrievedAt":815000000,"positions":[
          {"id":"0","symbol":"\(symbol)","state":"current","quantity":-2,"exchange":"MCX","product":"NRML","multiplier":1000,"realised":-25,"unrealised":1875,"lastPrice":160.125,\(fields)},
          {"id":"1","symbol":"CLOSED","state":"closed","quantity":0,"exchange":"NSE","product":"MIS","multiplier":1,"realised":42,"unrealised":0,"lastPrice":0,\(fields)},
          {"id":"2","symbol":"DELIVERY","state":"current","quantity":5,"exchange":"NSE","product":"CNC","multiplier":1,"realised":0,"unrealised":0,"lastPrice":160.125,\(fields)}
        ]}
        """
    }
#endif
