//
//  AccountFooter.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import Shared
    import SwiftUI

    /// One native account action pinned to the bottom of the sidebar.
    struct AccountFooter: View {
        @EnvironmentObject private var connection: BackendConnection
        /// The identity obtained after exchange and profile validation.
        let profile: AccountProfile

        @State private var showingAccount = false
        @FocusState private var accountFocused: Bool

        /// An avatar or initials beside readable, wrapping account text.
        var body: some View {
            Button {
                showingAccount = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    AccountAvatar(profile: profile)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(.headline)
                        Text(profile.userID).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($accountFocused)
            .accessibilityLabel("Open Kite account")
            .accessibilityValue("\(profile.name), \(profile.userID)")
            .sheet(isPresented: $showingAccount, onDismiss: { accountFocused = true }) {
                AccountSheet()
            }
            .onReceive(connection.$phase) { phase in
                if case .signedIn = phase {} else {
                    showingAccount = false
                }
            }
        }
    }

    /// Shared identity image with the sidebar's initials fallback.
    struct AccountAvatar: View {
        /// The identity whose avatar or initials appear.
        let profile: AccountProfile

        var body: some View {
            AsyncImage(url: profile.avatarURL) { image in
                image.resizable().scaledToFill().accessibilityHidden(true)
            } placeholder: {
                Text(initials)
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        }

        /// Up to two name initials, or the account identifier when no name is available.
        private var initials: String {
            let letters = profile.name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
            return letters.isEmpty ? String(profile.userID.prefix(2)).uppercased() : String(letters).uppercased()
        }
    }
#endif
