//
//  ConnectionAuthorization.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Shared
import Vapor

/// Protects app operations with the installation's separate connection token.
struct ConnectionAuthorization: AsyncMiddleware {
    /// The server-configured token, absent when the installation is not configured.
    let token: String?

    /// Rejects missing or incorrect authorization before invoking protected handlers.
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let supplied = request.headers.bearerAuthorization?.token, !supplied.isEmpty else {
            throw Abort(.unauthorized, reason: "Connection token required.")
        }
        guard let token, !token.isEmpty, token.utf8.allSatisfy({ (33 ... 126).contains($0) }) else {
            let response = Response(status: .serviceUnavailable)
            try response.content.encode(ConnectionProblem(code: .backendNotConfigured), as: .json)
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return response
        }
        guard token.utf8.secureCompare(to: supplied.utf8) else {
            throw Abort(.unauthorized, reason: "Connection token rejected.")
        }
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
}
