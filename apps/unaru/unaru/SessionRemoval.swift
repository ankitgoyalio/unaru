//
//  SessionRemoval.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Foundation
    import Shared

    /// Credential-free durable intent; cancellation must never become unconditional logout.
    enum SessionRemoval: Codable {
        /// Explicit logout removes all current saved authorization.
        case logout
        /// Cancellation removes only authorization originating in this attempt.
        case cancellation(String)
        /// An unreadable marker blocks restoration without broadening deletion scope.
        case unreadable

        /// Selects cancellation progress and recovery copy without reporting completed logout.
        var isCancellation: Bool {
            switch self {
            case .logout: false
            case .cancellation, .unreadable: true
            }
        }

        /// Returns provider uncertainty only for logout, after durable helper acknowledgement.
        func perform(using transport: BackendTransport, configuration: (url: URL, token: String)) async throws -> Bool {
            switch self {
            case .logout:
                let data = try await transport.send("logout", method: "POST", configuration: configuration)
                return try JSONDecoder().decode(LogoutResult.self, from: data).revocation != .confirmed
            case let .cancellation(id):
                guard !id.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                _ = try await transport.send("login/\(id)", method: "DELETE", configuration: configuration)
                return false
            case .unreadable:
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
#endif
