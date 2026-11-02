//
//  AccountSheet.swift
//  unaru
//
//  Created by Ankit Goyal on 02/11/2026.

#if os(macOS)
    import AppKit
    import Shared
    import SwiftUI

    /// Observes shared identity so every open sheet reflects refreshes and session expiry.
    struct AccountSheet: View {
        @EnvironmentObject private var connection: BackendConnection

        var body: some View {
            Group {
                if case let .signedIn(profile) = connection.phase {
                    AccountDetails(profile: profile)
                }
            }
            .onAppear { connection.refreshAccount() }
        }
    }

    /// Read-only details already obtained through the bundled backend.
    private struct AccountDetails: View {
        @EnvironmentObject private var connection: BackendConnection
        /// The current in-memory Kite account profile.
        let profile: AccountProfile
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Kite account")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if connection.isRefreshingAccount {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing account details")
                    }
                }
                .padding()
                if connection.accountRefreshFailed {
                    HStack {
                        Text("Couldn't refresh account details")
                        Spacer()
                        Button("Retry") { connection.refreshAccount() }
                            .disabled(connection.isRefreshingAccount)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 12) {
                            AccountAvatar(profile: profile)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(available(profile.name) ?? "Not available")
                                    .font(.title3.bold())
                                    .textSelection(.enabled)
                                detail("Kite ID", value: profile.userID, copyLabel: "Kite ID")
                            }
                        }
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                detail("Email", value: profile.email, copyLabel: "email")
                                detail("Broker", value: profile.broker)
                                detail("Account type", value: profile.accountType)
                            }
                            .padding(8)
                        } label: {
                            Text("Account details").accessibilityAddTraits(.isHeader)
                        }
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                detail("Exchanges", value: permissions(profile.exchanges))
                                detail("Products", value: permissions(profile.products))
                                detail("Order types", value: permissions(profile.orderTypes))
                            }
                            .padding(8)
                        } label: {
                            Text("Trading permissions").accessibilityAddTraits(.isHeader)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
                }
                Divider()
                HStack {
                    Button("Log Out", role: .destructive) { connection.logOut() }
                        .disabled(connection.isLoggingOut)
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(minWidth: 320, idealWidth: 440, maxWidth: 520, minHeight: 250, idealHeight: 480, maxHeight: 600)
            .onExitCommand { dismiss() }
        }

        private func detail(_ label: String, value: String?, copyLabel: String? = nil) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    Text(available(value) ?? (connection.isRefreshingAccount ? "Loading…" : "Not available"))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let copyLabel, let value = available(value) {
                        AccountCopyButton(label: copyLabel, value: value)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }

        /// Whitespace-only provider values cannot be inspected or copied.
        private func available(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }

        /// Keep raw provider codes, including unfamiliar codes, without inferring capabilities.
        private func permissions(_ codes: [String]?) -> String? {
            guard let codes else { return nil }
            if codes.isEmpty {
                return "None enabled"
            }
            guard codes.allSatisfy({ available($0) != nil }) else { return nil }
            return codes.joined(separator: ", ")
        }
    }

    /// Copy feedback belongs beside the activated action and expires independently.
    private struct AccountCopyButton: View {
        let label: String
        let value: String
        @State private var feedbackID: UUID?

        var body: some View {
            HStack(spacing: 6) {
                if feedbackID != nil {
                    Text("Copied").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    guard NSPasteboard.general.setString(value, forType: .string) else { return }
                    feedbackID = UUID()
                    NSAccessibility.post(
                        element: NSApp as Any,
                        notification: .announcementRequested,
                        userInfo: [.announcement: "Copied", .priority: NSAccessibilityPriorityLevel.medium.rawValue],
                    )
                } label: {
                    Label("Copy \(label)", systemImage: "doc.on.doc").labelStyle(.iconOnly)
                }
                .help("Copy \(label)")
            }
            .task(id: feedbackID) {
                guard feedbackID != nil else { return }
                do {
                    try await Task.sleep(for: .seconds(2))
                    feedbackID = nil
                } catch {}
            }
        }
    }
#endif
