//
//  PairCommand.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Vapor

/// Approves a visible pairing code using the backend owner's private data directory.
struct PairCommand: AsyncCommand {
    /// One explicit comparison code; no bearer credential is entered in the terminal.
    struct Signature: CommandSignature {
        /// Code displayed by the app requesting access.
        @Argument(name: "code", help: "Eight-digit pairing code shown in Unaru")
        var code: String
    }

    /// Explains that approval grants a Mac access to this backend.
    var help: String {
        "Approve a pairing request after comparing its code with Unaru."
    }

    /// Writes an approval marker consumed by the running backend, not a second credential registry.
    func run(using context: CommandContext, signature: Signature) async throws {
        try PairingStore.approve(code: signature.code, directory: PairingStore.defaultDirectory)
        context.console.print("Connection approved. Return to Unaru.")
    }
}
