//
//  ContentView.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import SwiftUI
#if os(macOS)
    import Shared
#endif

/// Displays the native Mac shell while preserving the other platforms' initial screen.
struct ContentView: View {
    #if os(macOS)
        /// The authenticated identity shared with the connection flow.
        @EnvironmentObject private var connection: BackendConnection
        /// Native sidebar visibility, initially expanded for a new window.
        @State private var visibility: NavigationSplitViewVisibility = .all
        /// Each window navigates independently while sharing source data.
        @State private var destination: PortfolioDestination? = .portfolio
        /// Keeps the selectable Portfolio parent expanded initially.
        @State private var portfolioExpanded = true
        /// Keeps native row navigation in the sidebar when a destination replaces the detail.
        @FocusState private var sidebarFocused: Bool
    #endif

    /// The current platform's initial content.
    var body: some View {
        #if os(macOS)
            navigation
                .onChange(of: signedInAccountID) { _, _ in destination = .portfolio }
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
        /// Native navigation keeps source content and session recovery vertically scrollable.
        private var navigation: some View {
            NavigationSplitView(columnVisibility: $visibility) {
                VStack {
                    if case let .signedIn(profile) = connection.phase {
                        List(selection: $destination) {
                            DisclosureGroup(isExpanded: $portfolioExpanded) {
                                Label("Holdings", systemImage: "list.bullet.rectangle")
                                    .tag(PortfolioDestination.holdings)
                                Label("Positions", systemImage: "arrow.left.arrow.right")
                                    .tag(PortfolioDestination.positions)
                                Label("Funds", systemImage: "banknote")
                                    .tag(PortfolioDestination.funds)
                            } label: {
                                NavigationLink(value: PortfolioDestination.portfolio) {
                                    Label("Portfolio", systemImage: "briefcase")
                                }
                            }
                            .tag(PortfolioDestination.portfolio)
                        }
                        .listStyle(.sidebar)
                        .focused($sidebarFocused)
                        .onChange(of: destination) { _, _ in sidebarFocused = true }
                        AccountFooter(profile: profile)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
            } detail: {
                ScrollView {
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
                        if case .signedIn = connection.phase {
                            if destination == .positions {
                                PositionsView(store: connection.positions)
                            } else if destination == .funds {
                                FundsView(store: connection.funds)
                            } else {
                                PortfolioView(destination: $destination, store: connection.portfolio)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .toolbar {
                Button("Refresh Portfolio", systemImage: "arrow.clockwise") { connection.refreshPortfolio() }
                    .help("Refresh portfolio sources (⌘R)")
                    .disabled(needsConnection)
            }
        }

        /// Authority transitions reset this window; profile revalidation of the same account preserves navigation.
        private var signedInAccountID: String? {
            if case let .signedIn(profile) = connection.phase {
                return profile.userID
            }
            return nil
        }

        /// Connection work stays modal until the account has been verified.
        private var needsConnection: Bool {
            if case .signedIn = connection.phase {
                return false
            }
            return true
        }
    #endif
}
