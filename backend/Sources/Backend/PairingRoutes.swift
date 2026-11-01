//
//  PairingRoutes.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation
import Shared
import Vapor

/// Registers bounded pairing endpoints without weakening authorization on app operations.
func pairingRoutes(_ app: Application, store: PairingStore) {
    let pairing = app.grouped("pairing")
    pairing.post { request async throws -> Response in
        let key = try await store.authenticate(request, approved: false)
        let offered = try request.content.decode(PairingRequest.self)
        guard offered.publicKey == key else { throw Abort(.unauthorized) }
        let status = try await store.start(publicKey: offered.publicKey, localProof: request.headers.first(name: "X-Unaru-Local-Pairing"))
        return try pairingResponse(status)
    }
    pairing.get(":id") { request async throws -> Response in
        let key = try await store.authenticate(request, approved: false)
        return try await pairingResponse(store.poll(id: request.parameters.get("id") ?? "", publicKey: key))
    }
    pairing.delete(":id") { request async throws -> HTTPStatus in
        let key = try await store.authenticate(request, approved: false)
        try await store.cancel(id: request.parameters.get("id") ?? "", publicKey: key)
        return .noContent
    }
}

/// Keeps pairing progress and private comparison codes out of intermediary caches.
private func pairingResponse(_ status: PairingStatus) throws -> Response {
    let response = Response(status: .ok)
    // Match the Mac client's Foundation date representation.
    try response.content.encode(status, using: JSONEncoder())
    response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
    return response
}
