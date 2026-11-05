//
//  KiteResponses.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import KiteConnect

/// Substitutes only Kite's outbound HTTP responses, leaving SDK encoding and decoding intact.
actor KiteResponses: KiteHTTPTransport {
    var requests: [KiteHTTPRequest] = []
    private var accessToken = "test-access"
    var exchangeStatus = 200
    var profileStatus = 200
    private var profileErrorType: String?
    private var profileBody: String?
    private var disconnectProfile = false
    private var profileTimeout = false
    private var invalidationBody = #"{"status":"success","data":true}"#
    private var invalidationDisconnect = false
    private var holdingsStatus = 200
    private var holdingsBody = #"{"status":"success","data":[]}"#
    private var holdingsFailure: URLError.Code?

    func setHoldings(status: Int = 200, body: String = #"{"status":"success","data":[]}"#, failure: URLError.Code? = nil) {
        holdingsStatus = status
        holdingsBody = body
        holdingsFailure = failure
    }

    private var positionsStatus = 200
    private var positionsBody = #"{"status":"success","data":{"net":[],"day":[]}}"#
    private var positionsFailure: URLError.Code?

    func setPositions(status: Int = 200, body: String = #"{"status":"success","data":{"net":[],"day":[]}}"#, failure: URLError.Code? = nil) {
        positionsStatus = status
        positionsBody = body
        positionsFailure = failure
    }

    private var heldPath: String?
    private var heldRequest: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func hold(_ path: String) {
        heldPath = path
    }

    func waitForHeldRequest() async {
        if heldRequest != nil {
            return
        }
        await withCheckedContinuation { observer = $0 }
    }

    func release() {
        heldPath = nil
        heldRequest?.resume()
        heldRequest = nil
    }

    func setInvalidation(body: String, disconnect: Bool = false) {
        invalidationBody = body
        invalidationDisconnect = disconnect
    }

    func setAccessToken(_ value: String) {
        accessToken = value
    }

    func setExchangeStatus(_ code: Int) {
        exchangeStatus = code
    }

    func setProfileTimeout(_ value: Bool) {
        profileTimeout = value
    }

    func setProfileStatus(_ code: Int) {
        profileStatus = code
    }

    func setProfileResponse(status: Int, errorType: String? = nil, body: String? = nil, disconnect: Bool = false) {
        profileStatus = status
        profileErrorType = errorType
        profileBody = body
        disconnectProfile = disconnect
    }

    func send(_ request: KiteHTTPRequest) async throws -> KiteHTTPResponse {
        requests.append(request)
        if heldPath == request.url.path {
            heldPath = nil
            await withCheckedContinuation { continuation in
                heldRequest = continuation
                observer?.resume()
                observer = nil
            }
        }
        if request.url.path == "/portfolio/positions" {
            if let positionsFailure {
                throw URLError(positionsFailure)
            }
            return KiteHTTPResponse(statusCode: positionsStatus, body: Data(positionsBody.utf8))
        }
        if request.url.path == "/portfolio/holdings" {
            if let holdingsFailure {
                throw URLError(holdingsFailure)
            }
            return KiteHTTPResponse(statusCode: holdingsStatus, body: Data(holdingsBody.utf8))
        }
        if request.method == .delete {
            if invalidationDisconnect {
                throw URLError(.networkConnectionLost)
            }
            return KiteHTTPResponse(statusCode: 200, body: Data(invalidationBody.utf8))
        }
        let exchange = request.url.path == "/session/token"
        if !exchange, profileTimeout {
            throw URLError(.timedOut)
        }
        if !exchange, disconnectProfile {
            throw URLError(.networkConnectionLost)
        }
        if !exchange, let profileBody {
            return KiteHTTPResponse(statusCode: profileStatus, body: Data(profileBody.utf8))
        }
        let status = exchange ? exchangeStatus : profileStatus
        let body: String
        if status == 200 {
            let credentials = exchange ? ",\"api_key\":\"test-key\",\"access_token\":\"\(accessToken)\",\"public_token\":\"test-public\",\"refresh_token\":\"\",\"login_time\":\"2026-11-01 10:00:00\"" : ""
            body = "{\"status\":\"success\",\"data\":{\"user_id\":\"AB1234\",\"user_name\":\"Asha Rao\",\"user_shortname\":\"Asha\",\"user_type\":\"individual\",\"email\":\"asha@example.invalid\",\"broker\":\"ZERODHA\",\"exchanges\":[\"NSE\"],\"products\":[\"CNC\"],\"order_types\":[\"LIMIT\"],\"avatar_url\":null,\"meta\":{\"demat_consent\":\"physical\"}\(credentials)}}"
        } else {
            body = "{\"status\":\"error\",\"error_type\":\"\(profileErrorType ?? (status == 403 ? "TokenException" : "NetworkException"))\",\"message\":\"Controlled failure\"}"
        }
        return KiteHTTPResponse(statusCode: status, body: Data(body.utf8))
    }
}
