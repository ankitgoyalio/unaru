//
//  ConnectionSettings.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import SwiftUI

    /// Connects this Mac to a backend without exposing its generated credential.
    struct ConnectionSettings: View {
        /// The connection shared with all main windows.
        @EnvironmentObject private var connection: BackendConnection
        /// The backend address, applied only when Connect is chosen.
        @State private var address = ""

        /// Native address entry and the current approval or verification result.
        var body: some View {
            Form {
                Section {
                    TextField("Backend address", text: $address, prompt: Text("http://127.0.0.1:8080"))
                        .accessibilityIdentifier("Backend address")
                    Text("Use HTTPS for a remote server. A backend on this Mac can use HTTP with a loopback address.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Unaru saves this Mac’s connection credential in Keychain. A local backend can connect through Keychain; a remote backend requires approval on the server.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Connect") { connection.connect(address: address) }
                    .keyboardShortcut(.defaultAction)
                switch connection.phase {
                case let .pairing(code):
                    Button("Cancel Connection") { connection.cancelLogin() }
                    PairingInstructions(code: code)
                case .checking:
                    ProgressView("Connecting…")
                    Button("Cancel Connection") { connection.cancelLogin() }
                case .signedOut:
                    Text("Connected. Return to the main window to sign in with Kite.")
                case let .configurationError(message):
                    Text(message)
                case .backendError, .unavailable:
                    Text("The backend is unavailable. Check its configuration and connection, then try again.")
                case .signedIn:
                    Text("Connected.")
                case .setup, .loggingIn, .loginUnavailable, .loginFailed:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            .padding()
            .frame(width: 520, height: 440)
            .onAppear { address = connection.address }
        }
    }

    /// Human comparison and approval steps, separate from the app's secret credential.
    struct PairingInstructions: View {
        /// Nonsecret code displayed only while the initiating app waits for approval.
        let code: String

        /// Makes the matching code and server action available visually and to VoiceOver.
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Approve This Connection").font(.headline)
                Text(code).font(.title.monospacedDigit())
                    .accessibilityLabel("Pairing code: \(code.map(String.init).joined(separator: " "))")
                Text("On your server, approve this code within five minutes:")
                Text("Backend pair \(code)").font(.body.monospaced()).textSelection(.enabled)
                Text("For a Swift source checkout, run swift run --package-path backend Backend pair followed by this code. Only approve the code shown on your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
#endif
