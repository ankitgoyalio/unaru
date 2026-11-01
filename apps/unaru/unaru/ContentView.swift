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
            Group {
                if case let .signedIn(profile) = connection.phase {
                    NavigationSplitView(columnVisibility: $visibility) {
                        VStack {
                            Spacer(minLength: 0)
                            AccountFooter(profile: profile)
                        }
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
                        .accessibilityLabel("Sidebar")
                    } detail: {
                        Color.clear
                    }
                } else {
                    ConnectionStatusView()
                }
            }
            .frame(minWidth: 600, minHeight: 400)
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
}
