//
//  LocalPairingKeychain.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import CryptoKit
    import Foundation
    import Security

    /// Same-user bootstrap for a native backend bound exclusively to Mac loopback.
    public enum LocalPairingKeychain {
        /// Reads only the bootstrap for the selected local port; macOS controls access.
        public static func read(port: Int) throws -> String? {
            var query = query(port: port)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound {
                return nil
            }
            guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            return value
        }

        /// Proves Keychain access for this public key without disclosing the bootstrap secret.
        public static func proof(secret: String, publicKey: String) -> String {
            Data(HMAC<SHA256>.authenticationCode(for: Data(publicKey.utf8), using: SymmetricKey(data: Data(secret.utf8)))).base64EncodedString()
        }

        /// Publishes the bootstrap in the owner's login Keychain; never uses an unrestricted ACL.
        public static func publish(_ secret: String, port: Int) throws {
            let query = query(port: port)
            let data = Data(secret.utf8)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        }

        /// Identifies a bootstrap independently of the app's private saved connection credential.
        private static func query(port: Int) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: "io.ankitgoyal.unaru.local-pairing",
             kSecAttrAccount as String: "loopback:\(port)"]
        }
    }
#endif
