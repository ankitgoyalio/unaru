//
//  ConnectionStorage.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import Foundation
    import Security

    /// Persists the address in defaults and the separate connection token in Keychain.
    struct ConnectionStorage {
        /// Nonsecret preferences for this installation or isolated UI-test run.
        let defaults: UserDefaults
        /// Keychain service separating production credentials from UI-test credentials.
        let service: String

        /// Selects production storage unless a debug UI test supplies an isolated UUID.
        init() {
            var name = "io.ankitgoyal.unaru.connection"
            #if DEBUG
                if let value = ProcessInfo.processInfo.environment["UNARU_TEST_STORAGE"], UUID(uuidString: value) != nil {
                    name += ".uitests.\(value)"
                    defaults = UserDefaults(suiteName: name)!
                } else {
                    defaults = .standard
                }
            #else
                defaults = .standard
            #endif
            service = name
            #if DEBUG
                if ProcessInfo.processInfo.environment["UNARU_TEST_RESET"] == "1", name.contains(".uitests.") {
                    defaults.removePersistentDomain(forName: name)
                    SecItemDelete(query as CFDictionary)
                }
            #endif
        }

        /// Identifies the one backend credential without putting the token in an address.
        private var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: "backend-connection"]
        }

        /// Reads a saved token, distinguishing missing credentials from a storage failure.
        func readToken() throws -> String {
            var request = query
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            if status == errSecItemNotFound {
                return ""
            }
            guard status == errSecSuccess, let data = result as? Data,
                  let credential = try? JSONDecoder().decode(StoredCredential.self, from: data),
                  credential.address == defaults.string(forKey: "backendAddress")
            else { throw StorageFailure() }
            return credential.token
        }

        /// Replaces the token before persisting the matching address.
        func save(address: String, token: String) throws {
            let data = try JSONEncoder().encode(StoredCredential(address: address, token: token))
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw StorageFailure() }
            defaults.set(address, forKey: "backendAddress")
        }

        /// Binds a token to its address so an interrupted save cannot send it to the previous server.
        private struct StoredCredential: Codable {
            /// The exact address saved with this credential.
            let address: String
            /// The separate app authorization token.
            let token: String
        }

        /// A storage failure deliberately omits credential values and system diagnostics.
        struct StorageFailure: Error {}
    }
#endif
