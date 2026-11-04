//
//  routes.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation
import Shared
import Vapor

/// Registers health, greeting, and protected app routes.
func routes(
    _ app: Application,
    connectionToken: String? = Environment.get("UNARU_CONNECTION_TOKEN"),
    login: KiteLogin = KiteLogin(),
    pairing: PairingStore? = nil,
) throws {
    if let pairing {
        pairingRoutes(app, store: pairing)
    }
    let protected = app.grouped(ConnectionAuthorization(token: connectionToken, pairing: pairing))
    protected.get("session") { _ async throws -> Response in
        let response = Response(status: .ok)
        do {
            try await response.content.encode(login.session(), as: .json)
        } catch let error as KiteLogin.RecoveryFailure {
            response.status = .serviceUnavailable
            try response.content.encode(ConnectionProblem(code: error.code), as: .json)
        }
        return response
    }
    protected.post("session", "save") { _ async throws -> Response in
        let response = Response(status: .ok)
        try await response.content.encode(login.retrySave(), as: .json)
        return response
    }
    protected.post("logout") { _ async throws -> Response in
        let response = Response(status: .ok)
        try await response.content.encode(login.logout(), as: .json)
        return response
    }
    protected.post("login") { _ async throws -> Response in
        let response = Response(status: .ok)
        // Match the Mac client's Foundation date representation.
        do {
            try await response.content.encode(login.start(), using: JSONEncoder())
        } catch KiteLogin.ConfigurationError.missingCredentials {
            response.status = .serviceUnavailable
            try response.content.encode(ConnectionProblem(code: .backendNotConfigured), as: .json)
        }
        return response
    }
    protected.get("login", ":id") { request async throws -> Response in
        let response = Response(status: .ok)
        try await response.content.encode(login.status(id: request.parameters.get("id") ?? ""), as: .json)
        return response
    }
    protected.delete("login", ":id") { request async throws -> HTTPStatus in
        try await login.cancel(id: request.parameters.get("id") ?? "")
        return .noContent
    }
    protected.get("profile") { _ async throws -> Response in
        let response = Response(status: .ok)
        do {
            try await response.content.encode(login.profile(), as: .json)
        } catch let error as KiteLogin.RecoveryFailure {
            response.status = .serviceUnavailable
            try response.content.encode(ConnectionProblem(code: error.code), as: .json)
        } catch let error as any AbortError where error.status == .unauthorized {
            response.status = .unauthorized
            try response.content.encode(ConnectionProblem(code: .kiteSignInRequired), as: .json)
        }
        return response
    }
    app.get("kite", "callback") { request async -> Response in
        let response: Response
        do {
            let query = try request.query.decode(KiteCallback.self)
            try await login.callback(state: query.state, requestToken: query.request_token, status: query.status)
            response = Response(status: .ok, body: .init(string: "Kite login received. Return to Unaru to finish."))
        } catch {
            response = Response(status: .badRequest, body: .init(string: "Login could not complete. Return to Unaru to try again."))
        }
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
        response.headers.replaceOrAdd(name: "Content-Security-Policy", value: "default-src 'none'; frame-ancestors 'none'")
        response.headers.contentType = .plainText
        return response
    }

    app.get { _ async in
        "It works!"
    }

    app.get("hello") { _ async -> String in
        "Hello, world!"
    }
}

/// Kite's registered callback query, including documented redirect_params passthrough.
private struct KiteCallback: Decodable {
    /// Random attempt authority, independent of app authorization.
    let state: String
    /// The one-time exchange credential supplied by Kite.
    let request_token: String?
    /// Kite's login outcome.
    let status: String?
}
