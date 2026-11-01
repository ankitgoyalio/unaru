//
//  BackendPairing.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import CryptoKit
    import Foundation
    import Shared

    /// Pairs a generated credential through local Keychain proof or server-owner approval.
    @MainActor
    struct BackendPairing {
        /// Shares the app's validated transport and redirect policy.
        let transport: BackendTransport

        /// Waits for approval, returning a credential only after the backend accepts it.
        func connect(address: String, savedCredential: String?, progress: @MainActor (PairingStatus, (url: URL, token: String)) -> Void) async throws -> (url: URL, token: String) {
            let key: Curve25519.Signing.PrivateKey = if let savedCredential, savedCredential.hasPrefix("unaru-key:"),
                                                        let bytes = Data(base64Encoded: String(savedCredential.dropFirst(10)))
            {
                try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
            } else {
                Curve25519.Signing.PrivateKey()
            }
            let credential = "unaru-key:" + key.rawRepresentation.base64EncodedString()
            let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
            let configuration = try BackendTransport.validate(address: address, token: credential)
            var localProof: String?
            let url = configuration.url
            if ["127.0.0.1", "localhost", "::1", "[::1]"].contains(url.host?.lowercased() ?? ""),
               url.scheme?.lowercased() == "http", url.path.isEmpty || url.path == "/",
               let secret = try? LocalPairingKeychain.read(port: url.port ?? 80)
            {
                localProof = LocalPairingKeychain.proof(secret: secret, publicKey: publicKey)
            }
            let data = try await transport.send("pairing", method: "POST", configuration: configuration,
                                                body: JSONEncoder().encode(PairingRequest(publicKey: publicKey)), localProof: localProof)
            var status = try JSONDecoder().decode(PairingStatus.self, from: data)
            guard UUID(uuidString: status.id) != nil else { throw BackendTransport.Failure.failed }
            let id = status.id
            let deadline = min(status.expiresAt, Date().addingTimeInterval(300))
            progress(status, configuration)
            while !status.approved {
                try Task.checkCancellation()
                guard Date() < deadline else { throw BackendTransport.Failure.failed }
                try await Task.sleep(for: .seconds(1))
                let data = try await transport.send("pairing/\(id)", configuration: configuration)
                status = try JSONDecoder().decode(PairingStatus.self, from: data)
                guard status.id == id else { throw BackendTransport.Failure.failed }
            }
            try Task.checkCancellation()
            return configuration
        }
    }
#endif
