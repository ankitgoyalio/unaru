//
//  ContentView.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import SwiftUI

/// Displays the native Mac shell while preserving the other platforms' initial screen.
struct ContentView: View {
    #if os(macOS)
        /// The authenticated identity shared with the connection flow.
        @EnvironmentObject private var connection: BackendConnection
        /// Native sidebar visibility, initially expanded for a new window.
        @State private var visibility: NavigationSplitViewVisibility = .all
    #endif

    /// The current platform's initial content.
    var body: some View {
        #if os(macOS)
            NavigationSplitView(columnVisibility: $visibility) {
                VStack {
                    Spacer(minLength: 0)
                    if case let .signedIn(profile) = connection.phase {
                        AccountFooter(profile: profile)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
            } detail: {
                VStack(alignment: .leading, spacing: 0) {
                    if connection.sessionSaveFailed {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sign-In Not Saved").font(.headline)
                                Text("You can keep using your Kite account. If you quit Unaru, you’ll need to sign in again.")
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Retry Saving") { connection.retrySavingSession() }
                                    .disabled(connection.isSavingSession)
                                if connection.isSavingSession {
                                    ProgressView("Saving Sign-In…")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .padding()
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(minWidth: 1024, minHeight: 794)
            .sheet(isPresented: .constant(needsConnection)) {
                ConnectionStatusView()
                    .frame(width: 400, height: 400)
                    .presentationSizing(.fitted)
                    .interactiveDismissDisabled()
            }
        #else
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
            }
            .padding()
        #endif
    }

    #if os(macOS)
        /// Connection work stays modal until the account has been verified.
        private var needsConnection: Bool {
            if case .signedIn = connection.phase {
                return false
            }
            return true
        }
    #endif
}
