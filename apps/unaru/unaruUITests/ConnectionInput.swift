//
//  ConnectionInput.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import AppKit
    import XCTest

    @MainActor
    extension unaruUITests {
        /// Uses normal paste commands because XCTest text synthesis can stall on Mac keyboard layouts.
        func pasteConnection(_ app: XCUIApplication, address: String, token: String) {
            let pasteboard = NSPasteboard.general
            let original = (pasteboard.pasteboardItems ?? []).map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            }
            defer {
                pasteboard.clearContents()
                pasteboard.writeObjects(original)
            }
            for (field, value) in [(app.textFields["Backend address"], address),
                                   (app.secureTextFields["Connection token"], token)]
            {
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.click()
                field.typeKey("a", modifierFlags: .command)
                pasteboard.clearContents()
                pasteboard.setString(value, forType: .string)
                field.typeKey("v", modifierFlags: .command)
            }
            app.buttons["Save Connection"].click()
        }
    }
#endif
