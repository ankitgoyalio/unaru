//
//  configure.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

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
