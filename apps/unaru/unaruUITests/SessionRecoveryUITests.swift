//
//  SessionRecoveryUITests.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import XCTest

    @MainActor
    extension unaruUITests {
        func testSavedSessionRecoveryRetriesWithoutRevealingIdentityOrOpeningBrowser() throws {
            for (code, heading, appearance) in [
                ("kiteSessionUnavailable", "Can’t Verify Kite Session", "Light"),
                ("sessionStorageUnavailable", "Saved Session Unavailable", "Dark"),
            ] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
                app.terminate()
                backend.respond(path: "/session", status: 503, body: "{\"code\":\"\(code)\"}")
                app.launch()
                XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 10))
                assertConnectionSheet(app)
                XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
                XCTAssertFalse(accountIdentity(app, containing: "AB1234").exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                XCTAssertTrue(app.buttons["Retry"].isHittable)
                let requests = backend.requests
                app.typeKey(.return, modifierFlags: [])
                let retried = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in backend.requests > requests }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [retried], timeout: 5), .completed)
                XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                capture(app, name: "Saved session retry - \(appearance)")
                backend.respond(path: "/session", status: 200, body: #"{"state":"signedIn","persistence":"saved"}"#)
                backend.respond(path: "/profile", status: 200, hold: true)
                app.buttons["Retry"].click()
                waitForPending(backend)
                XCTAssertFalse(app.buttons["Open Kite account"].exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                backend.releaseResponses()
                XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
                XCTAssertTrue(accountIdentity(app, containing: "AB1234").isHittable)
                XCTAssertFalse(app.buttons["Retry"].exists)
                XCTAssertFalse(app.staticTexts[heading].exists)
                XCTAssertEqual(backend.browserHandoffs, 1)
                XCTAssertEqual(backend.loginAttempts, 1)
            }
        }

        func testRelaunchValidatesBeforeRestoringIdentityWithoutBrowserLogin() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            backend.useAvatar(backend.address + "/missing-avatar")
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/profile", status: 200, hold: true)
            app.launch()
            waitForPending(backend)
            XCTAssertTrue(app.descendants(matching: .any)["Verifying Connection…"].firstMatch.exists)
            assertConnectionSheet(app)
            XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            backend.releaseResponses()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            XCTAssertTrue(accountIdentity(app, containing: "AB1234").exists)
            XCTAssertFalse(app.buttons["Retry"].exists)
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            XCTAssertEqual(backend.validations, 1)
            XCTAssertEqual(backend.browserHandoffs, 1)
            XCTAssertEqual(backend.loginAttempts, 1)
        }

        func testBackendRestartRequestsLoginWithoutShowingCachedIdentity() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            app.terminate()
            backend.loseSession()
            app.launch()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
            app.buttons["Sign in with Kite"].click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
        }

        func testRestorationRetriesNetworkAndProviderFailuresInSheet() throws {
            for (path, code, appearance) in [("/session", 0, "Light"), ("/profile", 503, "Dark")] {
                let backend = try ControlledBackend()
                defer { backend.stop() }
                let app = launch(backend: backend, appearance: appearance)
                defer { cleanUp(app) }
                beginLogin(app, backend: backend)
                backend.completeLogin()
                XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
                app.terminate()
                backend.respond(path: path, status: code)
                app.launch()
                XCTAssertTrue(app.staticTexts["Connection Unavailable"].waitForExistence(timeout: 20))
                XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
                XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
                assertConnectionSheet(app)
                capture(app, name: "Session recovery - \(appearance)")
                XCTAssertTrue(app.buttons["Retry"].isHittable)
                backend.respond(path: path, status: 200)
                app.typeKey(.return, modifierFlags: [])
                XCTAssertTrue(app.buttons["Retry"].waitForNonExistence(timeout: 10))
                XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
                XCTAssertTrue(accountIdentity(app, containing: "AB1234").isHittable)
                XCTAssertEqual(backend.browserHandoffs, 1)
                XCTAssertEqual(backend.loginAttempts, 1)
            }
        }

        func testRejectedInternalAuthorizationCanRetryWithoutSettings() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/profile", status: 401, body: "{}")
            app.launch()
            XCTAssertTrue(app.staticTexts["Unaru Couldn’t Start"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Sign in with Kite"].exists)
            XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
            backend.respond(path: "/profile", status: 200)
            backend.respond(status: 200)
            app.buttons["Retry"].click()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            XCTAssertEqual(backend.browserHandoffs, 1)
        }

        func testRevokedSessionOnLaunchOffersKiteLoginInsteadOfConnectionSettings() throws {
            let backend = try ControlledBackend()
            defer { backend.stop() }
            let app = launch(backend: backend)
            defer { cleanUp(app) }
            beginLogin(app, backend: backend)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
            app.terminate()
            backend.respond(path: "/profile", status: 401, body: "{\"code\":\"kiteSignInRequired\"}")
            app.launch()
            XCTAssertTrue(app.buttons["Sign in with Kite"].waitForExistence(timeout: 10))
            XCTAssertFalse(accountIdentity(app, containing: "Asha Rao").exists)
            XCTAssertFalse(app.staticTexts["Unaru Couldn’t Start"].exists)
            backend.respond(path: "/profile", status: 200)
            app.buttons["Sign in with Kite"].click()
            waitForHandoff(backend, count: 2)
            backend.completeLogin()
            XCTAssertTrue(accountIdentity(app, containing: "Asha Rao").waitForExistence(timeout: 10))
        }
    }
#endif
