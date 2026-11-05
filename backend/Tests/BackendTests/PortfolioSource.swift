//
//  PortfolioSource.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import Testing

/// Parameters vary only the external provider payload and source-specific response assertions.
enum PortfolioSource: CaseIterable, Sendable {
    case securities, mutualFunds, positions, funds

    var path: String {
        switch self {
        case .securities: "portfolio/holdings"
        case .mutualFunds: "portfolio/mutual-funds"
        case .positions: "portfolio/positions"
        case .funds: "portfolio/funds"
        }
    }

    var upstreamPath: String {
        switch self {
        case .securities, .positions: "/" + path
        case .mutualFunds: "/mf/holdings"
        case .funds: "/user/margins"
        }
    }

    var missingFieldPayload: String {
        switch self {
        case .securities, .mutualFunds: #"{"status":"success","data":[{"tradingsymbol":"UNKNOWN"}]}"#
        case .positions: #"{"status":"success","data":{"net":[{"tradingsymbol":"UNKNOWN"}],"day":[]}}"#
        case .funds: #"{"status":"success","data":{"equity":{"enabled":false}}}"#
        }
    }

    var populatedPayload: String {
        get throws {
            switch self {
            case .securities: try holdingsPayload([holdingFixture()])
            case .mutualFunds: try holdingsPayload([mutualFundHoldingFixture()])
            case .positions: try positionsPayload(net: [positionFixture()])
            case .funds: try fundsPayload()
            }
        }
    }

    var privateMarker: String {
        switch self {
        case .securities: "STOCK"
        case .mutualFunds: "Sample Growth Fund"
        case .positions: "SHORTFUT"
        case .funds: "1234.56789"
        }
    }

    func respond(_ transport: KiteResponses, status: Int = 200, body: String? = nil, failure: URLError.Code? = nil) async throws {
        switch self {
        case .securities: await transport.setHoldings(status: status, body: body ?? #"{"status":"success","data":[]}"#, failure: failure)
        case .mutualFunds: await transport.setMutualFunds(status: status, body: body ?? #"{"status":"success","data":[]}"#, failure: failure)
        case .positions: await transport.setPositions(status: status, body: body ?? #"{"status":"success","data":{"net":[],"day":[]}}"#, failure: failure)
        case .funds: try await transport.setFunds(status: status, body: body ?? fundsPayload(), failure: failure)
        }
    }
}

enum SourceFailure: CaseIterable, Sendable {
    case network, timeout, gateway, rateLimit, permission, malformed, missingField
}

enum AuthorityChange: CaseIterable, Sendable {
    case logout, newLogin, refresh, expiry
}

struct ObsoleteSourceScenario: Sendable {
    let status: Int
    let action: AuthorityChange

    static let all = [200, 403].flatMap { status in
        AuthorityChange.allCases.map { ObsoleteSourceScenario(status: status, action: $0) }
    }
}
