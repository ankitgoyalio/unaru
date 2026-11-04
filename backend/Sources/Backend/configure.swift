//
//  configure.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation
import KiteConnect
import Shared
import Vapor

/// Configures middleware and registers the backend routes.
func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // register routes
    app.asyncCommands.use(PairCommand(), as: "pair")
    guard app.environment != .testing else {
        try routes(app)
        return
    }
    // Approval commands must not open or overwrite the running server's registry.
    if app.environment.arguments.contains("pair") {
        return
    }
    if Environment.get("KITE_API_KEY")?.isEmpty != false || Environment.get("KITE_API_SECRET")?.isEmpty != false {
        app.logger.warning("Kite login is unavailable. Set KITE_API_KEY and KITE_API_SECRET in the process environment or the backend working directory's .env file.")
    }
    // The bundled helper uses launch-scoped authorization and no pairing registry.
    if Environment.get("UNARU_BUNDLED") == "1" {
        guard let token = Environment.get("UNARU_CONNECTION_TOKEN"), token.count >= 32,
              token.utf8.allSatisfy({ (33 ... 126).contains($0) }),
              Array(app.environment.arguments.suffix(5).prefix(4)) == ["serve", "--hostname", "127.0.0.1", "--port"],
              let port = Int(app.environment.arguments.last ?? ""), (1 ... 65535).contains(port)
        else { throw Abort(.internalServerError, reason: "Invalid bundled backend configuration.") }
        #if os(macOS)
            var namespace: UUID?
            var kiteConfiguration = try KiteConfiguration()
            #if DEBUG
                if let id = Environment.get("UNARU_TEST_STORAGE"), let uuid = UUID(uuidString: id) {
                    namespace = uuid
                    if let value = Environment.get("UNARU_TEST_KITE_URL"), let url = URL(string: value),
                       url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
                       url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty
                    {
                        kiteConfiguration = try KiteConfiguration(baseURL: url)
                    }
                }
            #endif
            let login = KiteLogin(store: KeychainKiteSessionStore(testNamespace: namespace), kiteConfiguration: kiteConfiguration)
            try routes(app, connectionToken: token, login: login)
        #else
            try routes(app, connectionToken: token)
        #endif
        return
    }
    let pairing = try PairingStore(directory: PairingStore.defaultDirectory)
    #if os(macOS)
        let arguments = app.environment.arguments
        let option: (String, String) -> String = { name, fallback in
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return fallback }
            return arguments[index + 1]
        }
        let hostname = option("--hostname", app.http.server.configuration.hostname)
        let port = Int(option("--port", String(app.http.server.configuration.port))) ?? 8080
        // Only an explicitly loopback-bound native server publishes automatic pairing authority.
        if ["127.0.0.1", "localhost", "::1"].contains(hostname) {
            do {
                try await LocalPairingKeychain.publish(pairing.localSecret(), port: port)
            } catch {
                app.logger.warning("Local Keychain pairing unavailable. Approve connection codes with the pair command.")
            }
        }
    #endif
    try routes(app, pairing: pairing)
}
