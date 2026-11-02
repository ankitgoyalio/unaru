//
//  entrypoint.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

import Foundation
import Logging
import NIOCore
import NIOPosix
import Vapor

/// Starts the Vapor backend and shuts it down after execution.
@main
enum Entrypoint {
    /// Creates, configures, and runs the application.
    static func main() async throws {
        // A bundled helper must not outlive its app, including after a crash or force quit.
        if ProcessInfo.processInfo.environment["UNARU_BUNDLED"] == "1" {
            DispatchQueue.global().async {
                _ = FileHandle.standardInput.readDataToEndOfFile()
                exit(0)
            }
        }
        var env = try Environment.detect()
        let app = try await Application.make(env)

        // This attempts to install NIO as the Swift Concurrency global executor.
        // You can enable it if you'd like to reduce the amount of context switching between NIO and Swift Concurrency.
        // Note: this has caused issues with some libraries that use `.wait()` and cleanly shutting down.
        // If enabled, you should be careful about calling async functions before this point as it can cause assertion failures.
        // let executorTakeoverSuccess = NIOSingletons.unsafeTryInstallSingletonPosixEventLoopGroupAsConcurrencyGlobalExecutor()
        // app.logger.debug("Tried to install SwiftNIO's EventLoopGroup as Swift's global concurrency executor", metadata: ["success": .stringConvertible(executorTakeoverSuccess)])

        do {
            // Application.make loads Vapor's dotenv files before logging reads LOG_LEVEL.
            try LoggingSystem.bootstrap(from: &env)
            app.environment = env
            app.logger = Logger(label: "codes.vapor.application")
            try await configure(app)
            if ProcessInfo.processInfo.environment["UNARU_BUNDLED"] == "1" {
                // startup returns only after the serve command has bound its listener.
                try await app.startup()
                try FileHandle.standardOutput.write(contentsOf: Data("UNARU_READY\n".utf8))
                try await app.running?.onStop.get()
            } else {
                try await app.execute()
            }
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
