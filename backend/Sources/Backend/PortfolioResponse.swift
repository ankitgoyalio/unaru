//
//  PortfolioResponse.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import Shared
import Vapor

/// Maps every portfolio read to the same credential-free recovery and authority response contract.
func portfolioResponse(_ read: () async throws -> some Encodable) async throws -> Response {
    let response = Response(status: .ok)
    do {
        try await response.content.encode(read(), using: JSONEncoder())
    } catch let error as KiteLogin.RecoveryFailure {
        response.status = .serviceUnavailable
        try response.content.encode(ConnectionProblem(code: error.code), as: .json)
    } catch let error as any AbortError where error.status == .unauthorized {
        response.status = .unauthorized
        try response.content.encode(ConnectionProblem(code: .kiteSignInRequired), as: .json)
    }
    return response
}
