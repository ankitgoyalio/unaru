//
//  BackendPairing.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import Foundation
    import Shared

    /// Pairs a generated credential through local Keychain proof or server-owner approval.
    @MainActor
    struct BackendPairing {
        /// Shares the app's validated transport and redirect policy.
        let transport: BackendTransport

        /// Waits for approval, returning a credential only after the backend accepts it.
        func connect(address: String, progress: @MainActor (String) -> Void) async throws -> (url: URL, token: String) {
            let credential = UUID().uuidString + UUID().uuidString
            let configuration = try BackendTransport.validate(address: address, token: credential)
            var localProof: String?
            let url = configuration.url
            if ["127.0.0.1", "localhost", "::1", "[::1]"].contains(url.host?.lowercased() ?? ""),
               url.scheme?.lowercased() == "http", url.path.isEmpty || url.path == "/"
            {
                localProof = try? LocalPairingKeychain.read(port: url.port ?? 80)
            }
            let data = try await transport.send("pairing", method: "POST", configuration: configuration,
                                                body: JSONEncoder().encode(PairingRequest(credential: credential)), localProof: localProof)
            var status = try JSONDecoder().decode(PairingStatus.self, from: data)
            guard UUID(uuidString: status.id) != nil else { throw BackendConnection.LoginFailure.failed }
            let id = status.id
            let deadline = min(status.expiresAt, Date().addingTimeInterval(300))
            var completed = false
            defer {
                if !completed {
                    Task { _ = try? await transport.send("pairing/\(id)", method: "DELETE", configuration: configuration) }
                }
            }
            while !status.approved {
                try Task.checkCancellation()
                guard Date() < deadline else { throw BackendConnection.LoginFailure.failed }
                progress(status.code)
                try await Task.sleep(for: .seconds(1))
                let data = try await transport.send("pairing/\(id)", configuration: configuration)
                status = try JSONDecoder().decode(PairingStatus.self, from: data)
                guard status.id == id else { throw BackendConnection.LoginFailure.failed }
            }
            try Task.checkCancellation()
            completed = true
            return configuration
        }
    }
#endif
