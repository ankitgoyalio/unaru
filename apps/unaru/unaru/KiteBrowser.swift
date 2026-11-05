//
//  KiteBrowser.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import AppKit
    import Foundation

    /// Validates Kite browser destinations before the system or isolated test handoff.
    @MainActor
    enum KiteBrowser {
        /// Opens only the expected HTTPS broker origin, without embedded credentials.
        static func open(_ url: URL, handoffData: Data, transport: BackendTransport, configuration: (url: URL, token: String)) async throws {
            guard url.scheme == "https", url.host == "kite.zerodha.com", url.path == "/connect/login",
                  url.user == nil, url.password == nil, url.fragment == nil else { throw BackendTransport.Failure.failed }
            #if DEBUG
                if BundledBackend.isUITest, ProcessInfo.processInfo.environment["UNARU_TEST_BROWSER"] == "1" {
                    _ = try await transport.send("test/browser", method: "POST", configuration: configuration, body: handoffData)
                } else {
                    guard NSWorkspace.shared.open(url) else { throw BackendTransport.Failure.failed }
                }
            #else
                guard NSWorkspace.shared.open(url) else { throw BackendTransport.Failure.failed }
            #endif
        }
    }
#endif
