//
//  FundsView.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Shared
    import SwiftUI

    /// Native segment summaries keep trading funds separate from investment performance.
    struct FundsView: View {
        @EnvironmentObject private var connection: BackendConnection
        /// One source state shared by every signed-in window.
        @ObservedObject var store: FundsStore
        /// A native sheet supports keyboard inspection without adding trading controls.
        @State private var inspected: TradingFundsSegment?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Trading Funds").font(.largeTitle).accessibilityAddTraits(.isHeader)
                Text("Trading availability and utilisation reported by Kite, separate from investment value and returns.")
                    .foregroundStyle(.secondary)
                if store.isLoading {
                    ProgressView("Loading trading funds…")
                }
                if store.failed {
                    Text("Couldn’t refresh trading funds").font(.headline)
                    if store.snapshot != nil {
                        Text("Stale funds — showing the previous retrieval.")
                    }
                    Button("Retry Funds") { connection.refreshFunds() }
                }
                if let snapshot = store.snapshot {
                    Text("Retrieved \(snapshot.retrievedAt.formatted(date: .abbreviated, time: .standard))")
                        .accessibilityIdentifier("Funds retrieval time")
                    if snapshot.segments.isEmpty {
                        ContentUnavailableView("No Trading Funds", systemImage: "banknote",
                                               description: Text("Kite returned no account segments."))
                    } else {
                        if !snapshot.segments.contains(where: \.enabled) {
                            Text("No Enabled Trading Segments").font(.headline)
                        }
                        ForEach(snapshot.segments) { segment in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(segment.enabled ? segment.displayName : "\(segment.displayName) — Disabled")
                                        .font(.headline).accessibilityAddTraits(.isHeader)
                                    if segment.enabled {
                                        LabeledContent("Available for trading", value: fundsAmount(segment.available))
                                        LabeledContent("Total utilisation", value: fundsAmount(segment.utilised))
                                        Button("Inspect \(segment.displayName) Funds") { inspected = segment }
                                    } else {
                                        Text("This segment is not enabled for trading.").foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }
                        }
                        ForEach(["equity", "commodity"].filter { expected in
                            !snapshot.segments.contains { $0.segment == expected }
                        }, id: \.self) { absent in
                            Text("\(absent.capitalized) — Not reported by Kite")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sheet(item: $inspected) { segment in FundsInspection(segment: segment) }
            .onReceive(store.$snapshot) { _ in inspected = nil }
            .onAppear { connection.refreshFunds() }
        }
    }
#endif
