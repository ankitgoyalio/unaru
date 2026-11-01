//
//  ConnectionSettings.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import SwiftUI

    /// Edits the backend connection in the standard Settings window.
    struct ConnectionSettings: View {
        /// The connection shared with all main windows.
        @EnvironmentObject private var connection: BackendConnection
        /// The address being edited, saved only by the explicit action.
        @State private var address = ""
        /// The token being edited in a secure field, never in defaults.
        @State private var token = ""
        /// A Keychain read error that must not silently replace an existing token.
        @State private var storageError = false

        /// Labeled fields, transport guidance, and connection feedback.
        var body: some View {
            Form {
                Section {
                    TextField("Backend address", text: $address, prompt: Text("http://localhost:8080"))
                        .accessibilityIdentifier("Backend address")
                    SecureField("Connection token", text: $token)
                        .accessibilityIdentifier("Connection token")
                    Text("Use HTTPS for a remote server. HTTP is supported for a backend on this Mac using a loopback address.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("The connection token is configured on your backend. It is separate from Kite authentication and is saved in Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if storageError {
                    Text("The saved connection could not be read. Unlock Keychain and reopen Settings, or enter the connection token again.")
                }
                Button("Save Connection") {
                    if connection.save(address: address, token: token) {
                        address = connection.address
                        storageError = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                switch connection.phase {
                case .checking:
                    ProgressView("Verifying connection…")
                case .signedOut:
                    Text("Connection verified. Your backend requires Kite sign-in.")
                case let .configurationError(message):
                    Text(message)
                case .backendError:
                    Text("Set UNARU_CONNECTION_TOKEN on the backend, then retry in the main window.")
                case .unavailable:
                    Text("The backend could not be reached or returned an unexpected response. Retry in the main window.")
                case .setup, .loggingIn, .loginUnavailable, .loginFailed, .signedIn:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            .padding()
            .frame(width: 520, height: 440)
            .onAppear {
                address = connection.address
                do {
                    token = try connection.savedToken()
                    storageError = false
                } catch {
                    storageError = true
                }
            }
        }
    }
#endif
