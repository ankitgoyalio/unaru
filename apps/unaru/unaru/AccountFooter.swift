//
//  AccountFooter.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import Shared
    import SwiftUI

    /// Informational identity pinned to the bottom of the native sidebar.
    struct AccountFooter: View {
        /// The identity obtained after exchange and profile validation.
        let profile: AccountProfile

        /// An avatar or initials beside readable, wrapping account text.
        var body: some View {
            HStack(alignment: .center, spacing: 10) {
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(.headline)
                    Text(profile.userID).font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .accessibilityElement(children: .contain)
        }

        /// Up to two name initials, or the account identifier when no name is available.
        private var initials: String {
            let letters = profile.name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
            return letters.isEmpty ? String(profile.userID.prefix(2)).uppercased() : String(letters).uppercased()
        }
    }
#endif
