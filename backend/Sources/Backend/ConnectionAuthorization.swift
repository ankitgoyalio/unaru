//
//  ConnectionAuthorization.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Shared
import Vapor

/// Protects app operations with approved signed keys or a legacy connection token.
struct ConnectionAuthorization: AsyncMiddleware {
    /// An optional server-configured token accepted for existing clients.
    let token: String?

    /// Credentials approved by the backend owner.
    var pairing: PairingStore?

    /// Rejects missing or incorrect authorization before invoking protected handlers.
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let pairing, request.headers.first(name: "X-Unaru-Key") != nil {
            _ = try await pairing.authenticate(request)
            let response = try await next.respond(to: request)
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return response
        }
        guard let supplied = request.headers.bearerAuthorization?.token, !supplied.isEmpty else {
            throw Abort(.unauthorized, reason: "Connection authorization required.")
        }
        guard let token, !token.isEmpty, token.utf8.allSatisfy({ (33 ... 126).contains($0) }) else {
            if pairing != nil {
                throw Abort(.unauthorized, reason: "Connect this Mac again in Settings.")
            }
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
