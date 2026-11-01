//
//  routes.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Vapor

/// Registers the scaffold health and greeting routes.
func routes(_ app: Application) throws {
    app.get { _ async in
        "It works!"
    }

    app.get("hello") { _ async -> String in
        "Hello, world!"
    }
}
