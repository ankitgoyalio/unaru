//
//  SourceInspectionStatus.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import SwiftUI

    /// Keeps a retained row's retrieval and recovery visible while its inspection is open.
    struct SourceInspectionStatus: View {
        /// Names the independently refreshed source being inspected.
        let source: LocalizedStringKey
        /// A pending read does not make the retained row newly retrieved.
        let isLoading: Bool
        /// Temporary failure preserves the row and its successful retrieval time.
        let failed: Bool
        /// Retrieval time never establishes a market-price or NAV date.
        let retrievedAt: Date?
        /// Source-specific actions remain unambiguous in accessibility navigation.
        let retryTitle: LocalizedStringKey
        /// Retries only this source under the existing account's authority.
        let retry: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(source).font(.headline)
                if isLoading {
                    ProgressView("Refreshing source…")
                    Text("Showing the previous retrieval while refreshing.")
                } else if failed {
                    Text("Couldn’t refresh this source.")
                    Text("Stale data — showing the previous retrieval.")
                    Button(retryTitle, action: retry)
                }
                if let retrievedAt {
                    Text("Retrieved \(retrievedAt.formatted(date: .abbreviated, time: .standard))")
                        .accessibilityIdentifier("Inspection source retrieval time")
                }
            }
        }
    }
#endif
