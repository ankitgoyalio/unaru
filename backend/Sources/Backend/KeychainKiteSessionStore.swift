//
//  KeychainKiteSessionStore.swift
//  unaru
//
//  Created by Ankit Goyal on 04/11/2026.

#if os(macOS)
    import Crypto
    import Foundation
    import LocalAuthentication
    import Security

    /// Helper-private login Keychain items, independent of app sandbox inheritance.
    struct KeychainKiteSessionStore: KiteSessionStore {
        /// Fixed production service or an explicitly isolated Debug test namespace.
        let service: String

        #if DEBUG
            /// Dynamic failure injection is available only with an isolated test namespace.
            private let testFailureFile: URL?
        #endif

        /// Creates the helper's store; tests must supply a unique service namespace.
        init(testNamespace: UUID? = nil) {
            service = testNamespace.map { "io.ankitgoyal.unaru.kite-session.test.\($0.uuidString)" }
                ?? "io.ankitgoyal.unaru.kite-session"
            #if DEBUG
                testFailureFile = testNamespace.flatMap { _ in
                    ProcessInfo.processInfo.environment["UNARU_TEST_SESSION_FAILURE_FILE"].map { URL(fileURLWithPath: $0) }
                }
            #endif
        }

        /// Returns nil only for item absence; denies interactive prompts in a background helper.
        func load(apiKey: String) throws -> SavedKiteSession? {
            var query = query(apiKey)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            if status == errSecItemNotFound {
                return nil
            }
            try check(status)
            guard let data = value as? Data else { throw CocoaError(.coderReadCorrupt) }
            return try JSONDecoder().decode(SavedKiteSession.self, from: data)
        }

        /// Replaces an existing item atomically; the helper's designated requirement owns its ACL.
        func save(_ session: SavedKiteSession, apiKey: String) throws {
            try checkTestFailure("save")
            let query = query(apiKey)
            let data = try JSONEncoder().encode(session)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            try check(status)
        }

        /// Absence is already signed out; access failures remain failures.
        func delete(apiKey: String) throws {
            try checkTestFailure("delete")
            let status = SecItemDelete(query(apiKey) as CFDictionary)
            if status != errSecItemNotFound {
                try check(status)
            }
        }

        /// Deterministic lifecycle failures never apply to production or Release storage.
        private func checkTestFailure(_ operation: String) throws {
            #if DEBUG
                if let testFailureFile,
                   let failure = try? String(contentsOf: testFailureFile, encoding: .utf8),
                   failure.trimmingCharacters(in: .whitespacesAndNewlines) == operation
                {
                    throw CocoaError(.fileWriteNoPermission)
                }
            #endif
        }

        /// Hashes the configuration key and leaves the validated account inside the protected value.
        private func query(_ apiKey: String) -> [String: Any] {
            let context = LAContext()
            context.interactionNotAllowed = true
            return [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined(),
                    kSecUseAuthenticationContext as String: context]
        }

        /// Carries only OS status, never token or account data.
        private func check(_ status: OSStatus) throws {
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        }
    }
#endif
