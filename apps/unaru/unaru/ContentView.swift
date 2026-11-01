//
//  ContentView.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import SwiftUI

/// Displays the native Mac shell while preserving the other platforms' initial screen.
struct ContentView: View {
    #if os(macOS)
        /// Native sidebar visibility, initially expanded for a new window.
        @State private var visibility: NavigationSplitViewVisibility = .all
    #endif

    /// The current platform's initial content.
    var body: some View {
        #if os(macOS)
            NavigationSplitView(columnVisibility: $visibility) {
                Color.clear
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
                    .accessibilityLabel("Sidebar")
            } detail: {
                ConnectionStatusView()
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
