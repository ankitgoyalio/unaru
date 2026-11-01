//
//  SessionRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testRelaunchValidatesBeforeRestoringIdentityWithoutBrowserLogin() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.useAvatar(backend.address + "/missing-avatar")
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/profile", status: 200, hold: true)
            app.launch()
            waitForPending(backend)
            XCTAssertTrue(app.descendants(matching: .any)["Verifying Connection…"].firstMatch.exists)
            assertConnectionScreen(app)
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            backend.releaseResponses()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["AB1234"].exists)
            XCTAssertTrue(app.staticTexts["AR"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Retry"].exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            XCTAssertEqual(backend.validations, 1)
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }

        func testBackendRestartRequestsLoginWithoutShowingCachedIdentity() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            app.terminate()
            backend.loseSession()
            app.launch()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            app.buttons["Sign in with Kite"].click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
        }

        func testRestorationRetriesNetworkAndProviderFailuresOnDedicatedScreen() throws {
            for (path, code, appearance) in [("/session", 0, "Light"), ("/profile", 503, "Dark")] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
                app.terminate()
                backend.respond(path: path, status: code)
                app.launch()
                XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 20))
                XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                assertConnectionScreen(app)
                capture(app, name: "Session recovery - \(appearance)")
                XCTAssertTrue(app.buttons["Retry"].isHittable)
                backend.respond(path: path, status: 200)
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(app.buttons["Retry"].waitForNonExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["AB1234"].isHittable)
                XCTAssertEqual(backend.browserHandoffs, 1)
                XCTAssertEqual(backend.loginAttempts, 1)
                app.typeKey(",", modifierFlags: .command)
                XCTAssertTrue(app.textFields["Backend address"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.textFields["Backend address"].value as? String, backend.address)
            }
        }

        func testRejectedConnectionCredentialsDuringProfileRestorationOpenSettings() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/profile", status: 401, body: "{}")
            app.launch()
            XCTAssertTrue(app.staticTexts["Check Connection Settings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            app.buttons["Configure Connection"].click()
            backend.respond(path: "/profile", status: 200)
            backend.respond(status: 200)
            connect(app, address: backend.address)
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testReconnectingClearsAuthenticatedPresentation() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            app.typeKey(",", modifierFlags: .command)
            backend.respond(status: 401)
            connect(app, address: backend.address)
            XCTAssertTrue(app.staticTexts["Check Connection Settings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            backend.respond(status: 200)
            connect(app, address: backend.address)
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testChangingAddressRejectsDelayedRestorationIdentity() throws {
            let previous = try ControlledBackend()
            let current = try ControlledBackend()
            defer { previous.stop(); current.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: previous)
            previous.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            app.terminate()
            previous.respond(path: "/profile", status: 200, hold: true,
                             body: "{\"name\":\"Obsolete Person\",\"userID\":\"OLD123\"}")
            app.launch()
            waitForPending(previous)
            app.typeKey(",", modifierFlags: .command)
            connect(app, address: current.address)
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            previous.releaseResponses()
            let obsolete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { app.staticTexts["Obsolete Person"].exists }
            }, object: nil)
            obsolete.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [obsolete], timeout: 1), .completed)
            XCTAssertTrue(app.buttons["Sign in with Kite"].exists)
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
        }

        func testRevokedSessionOnLaunchOffersKiteLoginInsteadOfConnectionSettings() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch()
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/profile", status: 401, body: "{\"code\":\"kiteSignInRequired\"}")
            app.launch()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Asha Rao"].exists)
            XCTAssertFalse(app.staticTexts["Check Connection Settings"].exists)
            backend.respond(path: "/profile", status: 200)
            app.buttons["Sign in with Kite"].click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(app.staticTexts["Asha Rao"].waitForExistence(timeout: 10))
        }
    }
#endif
