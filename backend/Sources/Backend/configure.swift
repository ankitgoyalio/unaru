//
//  configure.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Vapor

/// Configures middleware and registers the backend routes.
func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // register routes
    try routes(app)
}
