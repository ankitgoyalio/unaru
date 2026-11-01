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

        /// Forces deterministic appearance only for Debug UI tests with isolated storage.
        private var testColorScheme: ColorScheme? {
            #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                guard let storage = environment["UNARU_TEST_STORAGE"], UUID(uuidString: storage) != nil else { return nil }
                switch environment["UNARU_TEST_APPEARANCE"] {
                case "Light": return .light
                case "Dark": return .dark
                default: return nil
                }
            #else
                return nil
            #endif
        }
    #endif

    /// The main window and platform-appropriate commands.
    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                ContentView()
                    .environmentObject(connection)
                    .preferredColorScheme(testColorScheme)
            }
            .commands { SidebarCommands() }
            Settings {
                ConnectionSettings()
                    .environmentObject(connection)
                    .preferredColorScheme(testColorScheme)
            }
        #else
            WindowGroup {
                ContentView()
            }
        #endif
    }
}
