//
//  ConnectionStatusView.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import SwiftUI

    /// Sign-in and recovery presented in a modal sheet over the main window.
    struct ConnectionStatusView: View {
        /// The bundled backend and its verified Kite session.
        @EnvironmentObject private var connection: BackendConnection

        /// The action appropriate to startup, sign-in, or recovery.
        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    switch connection.phase {
                    case .starting:
                        ProgressView("Starting Unaru…")
                    case .startupFailed:
                        Text("Unaru Couldn’t Start").font(.title2)
                        Text("Unaru couldn’t start its local service. Close any other running copy of Unaru or service using port 8080, then retry.")
                        retryButton
                    case .checking:
                        ProgressView("Verifying Connection…")
                    case .signedOut:
                        Text(connection.isLoggingOut ? "Logging Out…" : "Kite Sign-In Required").font(.title2)
                        if connection.isLoggingOut {
                            ProgressView("Ending Kite API Session…")
                        }
                        if connection.logoutUnconfirmed {
                            Text("Unaru signed out locally, but couldn’t confirm that the Kite API session ended.")
                                .accessibilityIdentifier("Logout uncertainty")
                        }
                        Button("Sign in with Kite") { connection.signIn() }
                            .disabled(connection.isLoggingOut)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    case .loggingIn:
                        ProgressView("Complete Sign-In in Your Browser")
                        Text("Return here after signing in. This attempt expires after five minutes.")
                        Button("Cancel Sign-In") { connection.cancelLogin() }
                            .keyboardShortcut(.cancelAction)
                    case .loginUnavailable:
                        Text("Sign-In Temporarily Unavailable").font(.title2)
                        Text("Check your connection, then retry to finish signing in.")
                        Button("Retry Sign-In") { connection.retryLogin() }
                        Button("Cancel Sign-In") { connection.cancelLogin() }
                    case .loginFailed:
                        Text("Sign-In Not Completed").font(.title2)
                        Text("The login was cancelled, rejected, or expired. You can try again.")
                        Button("Sign in with Kite") { connection.signIn() }
                            .buttonStyle(.borderedProminent)
                    case .signedIn:
                        Color.clear
                    case .backendError:
                        Text("Set Up Kite").font(.title2)
                        Text("Add your Kite API key and secret to the .env file in Unaru’s configuration folder, then choose Retry.")
                        Button("Open Configuration Folder") { connection.openConfiguration() }
                        retryButton
                    case .logoutFailed:
                        Text("Couldn’t Finish Logging Out").font(.title2)
                        Text("Unaru couldn’t confirm removal of your saved sign-in. Retry to finish logging out before signing in again.")
                        Button("Retry Log Out") { connection.retry() }
                            .keyboardShortcut(.defaultAction)
                    case .sessionUnavailable:
                        Text("Can’t Verify Kite Session").font(.title2)
                        Text("Unaru couldn’t verify your saved Kite session. Check your internet connection, then retry.")
                        retryButton
                    case .storageUnavailable:
                        Text("Saved Session Unavailable").font(.title2)
                        Text("Unaru couldn’t read your saved Kite session from Keychain. Retry to check it again.")
                        retryButton
                    case .unavailable:
                        Text("Connection Unavailable").font(.title2)
                        Text("Check your internet connection, then retry. Your Kite session may still be available.")
                        retryButton
                    }
                }
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("Connection sheet")
        }

        /// Retries verification or restarts a failed local service.
        private var retryButton: some View {
            Button("Retry") { connection.retry() }
                .keyboardShortcut(.defaultAction)
        }
    }
#endif
