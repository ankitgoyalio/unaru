//
//  ConnectionStatusView.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import SwiftUI

    /// Keeps setup and recovery reachable in the main area even with the sidebar hidden.
    struct ConnectionStatusView: View {
        /// The currently selected backend and its verified state.
        @EnvironmentObject private var connection: BackendConnection

        /// The action appropriate to the current connection state.
        var body: some View {
            VStack(spacing: 16) {
                switch connection.phase {
                case .setup:
                    Text("Connect to Your Backend").font(.title2)
                    Text("Configure your self-hosted backend to get started.")
                    settingsLink
                case .checking:
                    ProgressView("Verifying Connection…")
                    settingsLink
                case .signedOut:
                    Text("Kite Sign-In Required").font(.title2)
                    Text("Your backend connection is verified. No Kite account is signed in.")
                    settingsLink
                case let .configurationError(message):
                    Text("Check Connection Settings").font(.title2)
                    Text(message)
                    settingsLink
                case .backendError:
                    Text("Configure Your Backend").font(.title2)
                    Text("The server has no valid connection token. Set UNARU_CONNECTION_TOKEN on the backend, then retry.")
                    retryButton
                    settingsLink
                case .unavailable:
                    Text("Connection Unavailable").font(.title2)
                    Text("Check that your backend is running and the address is correct, then retry.")
                    retryButton
                    settingsLink
                }
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        /// Opens native Settings through the same destination as the app menu command.
        private var settingsLink: some View {
            SettingsLink {
                Text("Configure Connection")
            }
            .buttonStyle(.borderedProminent)
        }

        /// Repeats verification without altering the stored address or token.
        private var retryButton: some View {
            Button("Retry") { connection.verify() }
        }
    }
#endif
