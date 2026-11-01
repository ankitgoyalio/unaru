//
//  unaruApp.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import SwiftUI

/// Creates the application's main window and native Mac connection Settings.
@main
struct unaruApp: App {
    #if os(macOS)
        /// One shared backend connection across Settings and app windows.
        @StateObject private var connection = BackendConnection()
    #endif

    /// The main window and platform-appropriate commands.
    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                ContentView()
                    .environmentObject(connection)
            }
            .commands { SidebarCommands() }
            Settings {
                ConnectionSettings()
                    .environmentObject(connection)
            }
        #else
            WindowGroup {
                ContentView()
            }
        #endif
    }
}
