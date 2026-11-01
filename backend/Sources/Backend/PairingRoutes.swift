//
//  PairingRoutes.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Shared
import Vapor

/// Registers bounded pairing endpoints without weakening authorization on app operations.
func pairingRoutes(_ app: Application, store: PairingStore) {
    let pairing = app.grouped("pairing")
    pairing.post { request async throws -> Response in
        let offered = try request.content.decode(PairingRequest.self)
        let status = try await store.start(credential: offered.credential, localProof: request.headers.first(name: "X-Unaru-Local-Pairing"))
        return try pairingResponse(status)
    }
    pairing.get(":id") { request async throws -> Response in
        guard let credential = request.headers.bearerAuthorization?.token else { throw Abort(.unauthorized) }
        return try await pairingResponse(store.poll(id: request.parameters.get("id") ?? "", credential: credential))
    }
    pairing.delete(":id") { request async throws -> HTTPStatus in
        guard let credential = request.headers.bearerAuthorization?.token else { throw Abort(.unauthorized) }
        try await store.cancel(id: request.parameters.get("id") ?? "", credential: credential)
        return .noContent
    }
}

/// Keeps pairing progress and private comparison codes out of intermediary caches.
private func pairingResponse(_ status: PairingStatus) throws -> Response {
    let response = Response(status: .ok)
    try response.content.encode(status, as: .json)
    response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
    return response
}
