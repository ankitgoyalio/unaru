//
//  routes.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Shared
import Vapor

/// Registers health, greeting, and protected app routes.
func routes(_ app: Application, connectionToken: String? = Environment.get("UNARU_CONNECTION_TOKEN")) throws {
    app.grouped(ConnectionAuthorization(token: connectionToken)).get("session") { _ async throws -> Response in
        let response = Response(status: .ok)
        try response.content.encode(SessionStatus(state: .signedOut), as: .json)
        return response
    }

    app.get { _ async in
        "It works!"
    }

    app.get("hello") { _ async -> String in
        "Hello, world!"
    }
}
