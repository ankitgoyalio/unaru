//
//  BundledBackend.swift
//  unaru
//
//  Created by Ankit Goyal on 02/11/2026.

#if os(macOS)
    import AppKit
    import CryptoKit
    import Foundation

    /// Owns the private helper process for this app launch.
    @MainActor
    final class BundledBackend {
        /// Kite's registered loopback callback uses a stable port.
        static var address: String {
            #if DEBUG
                if isUITest, let value = ProcessInfo.processInfo.environment["UNARU_TEST_BACKEND_PORT"],
                   let port = Int(value), (1 ... 65535).contains(port)
                {
                    return "http://127.0.0.1:\(port)"
                }
            #endif
            return "http://127.0.0.1:8080"
        }

        /// The running helper, never an independently discovered server.
        private var process: Process?
        /// Closing this pipe also stops the helper if the app is killed.
        private var lifetime: Pipe?
        /// Private readiness channel, written only after the helper binds its listener.
        private var output: Pipe?
        /// Accumulates readiness bytes across pipe read boundaries.
        private var outputBuffer = Data()
        /// The child has confirmed ownership of its loopback listener.
        private var ready = false
        /// Rejects queued readiness callbacks from a stopped helper.
        private var launchID = UUID()
        /// Stops the helper when the user quits normally.
        private var terminationObserver: NSObjectProtocol?
        /// Authorization generated for this launch, never saved to disk.
        private let token = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }

        /// Restricts debug overrides to isolated UI-test installations.
        static var isUITest: Bool {
            #if DEBUG
                UUID(uuidString: ProcessInfo.processInfo.environment["UNARU_TEST_STORAGE"] ?? "") != nil
            #else
                false
            #endif
        }

        /// Keeps Kite configuration in the app's writable support directory.
        static var configurationDirectory: URL {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            #if DEBUG
                if isUITest, let id = ProcessInfo.processInfo.environment["UNARU_TEST_STORAGE"] {
                    return root.appendingPathComponent("Unaru/UITests/\(id)", isDirectory: true)
                }
            #endif
            return root.appendingPathComponent("Unaru", isDirectory: true)
        }

        /// Credential-free intent survives helper failure and application relaunch.
        private static var logoutMarker: URL {
            configurationDirectory.appendingPathComponent(".pending-kite-logout")
        }

        /// Startup must finish removal before requesting any restorable session.
        static var hasPendingLogout: Bool {
            FileManager.default.fileExists(atPath: logoutMarker.path)
        }

        /// A completed logout requires both helper deletion and clearing its local intent.
        static func setLogoutPending(_ pending: Bool) throws {
            if pending {
                try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try Data("pending\n".utf8).write(to: logoutMarker, options: .atomic)
            } else if hasPendingLogout {
                try FileManager.default.removeItem(at: logoutMarker)
            }
        }

        /// Connects lifetime cleanup to the application's termination notification.
        init() {
            terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }

        isolated deinit {
            if let terminationObserver {
                NotificationCenter.default.removeObserver(terminationObserver)
            }
            stop()
        }

        /// Launches only the embedded executable with an internal authorization token.
        func start() throws -> (url: URL, token: String) {
            #if DEBUG
                if Self.isUITest, let address = ProcessInfo.processInfo.environment["UNARU_TEST_BACKEND_ADDRESS"] {
                    guard let url = URL(string: address), url.scheme == "http", url.host == "127.0.0.1",
                          url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                          url.path.isEmpty else { throw StartupFailure() }
                    return (url, "ui-test-token")
                }
            #endif
            if process?.isRunning == true {
                return (URL(string: Self.address)!, token)
            }
            stop()
            let directory = Self.configurationDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let dotenv = directory.appendingPathComponent(".env")
            if !FileManager.default.fileExists(atPath: dotenv.path) {
                try Data("# Register http://127.0.0.1:8080/kite/callback with Kite.\nKITE_API_KEY=\nKITE_API_SECRET=\n".utf8).write(to: dotenv, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dotenv.path)
            }
            let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Backend")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw StartupFailure() }
            let helper = Process()
            helper.executableURL = executable
            helper.arguments = ["serve", "--hostname", "127.0.0.1", "--port", String(URL(string: Self.address)!.port!)]
            helper.currentDirectoryURL = directory
            // Do not inherit remote deployment settings, credentials, or dotenv selection.
            helper.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(),
                                  "UNARU_BUNDLED": "1", "UNARU_CONNECTION_TOKEN": token]
            #if DEBUG
                if Self.isUITest {
                    helper.environment?["UNARU_TEST_STORAGE"] = ProcessInfo.processInfo.environment["UNARU_TEST_STORAGE"]
                    helper.environment?["UNARU_TEST_KITE_URL"] = ProcessInfo.processInfo.environment["UNARU_TEST_KITE_URL"]
                }
            #endif
            let pipe = Pipe()
            helper.standardInput = pipe
            let output = Pipe()
            let launchID = launchID
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                // read(upToCount:) waits to fill its buffer on a pipe; availableData
                // delivers a short readiness marker while the child stays running.
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                }
                Task { @MainActor [weak self] in
                    guard let self, self.launchID == launchID else { return }
                    outputBuffer.append(data)
                    if String(decoding: outputBuffer, as: UTF8.self).components(separatedBy: "\n").contains("UNARU_READY") {
                        ready = true
                    }
                    // Retain enough for a split marker without accumulating service logs.
                    outputBuffer = outputBuffer.suffix(1024)
                }
            }
            helper.standardOutput = output
            helper.standardError = FileHandle.nullDevice
            try helper.run()
            try output.fileHandleForWriting.close()
            self.output = output
            // The parent owns only the writer; the child owns the reader.
            try pipe.fileHandleForReading.close()
            process = helper
            lifetime = pipe
            return (URL(string: Self.address)!, token)
        }

        /// Waits on child IPC before any credential is sent to the callback port.
        func waitUntilReady() async throws {
            #if DEBUG
                if Self.isUITest, ProcessInfo.processInfo.environment["UNARU_TEST_BACKEND_ADDRESS"] != nil {
                    return
                }
            #endif
            let deadline = Date().addingTimeInterval(15)
            while !ready {
                try Task.checkCancellation()
                guard isRunning, Date() < deadline else { throw StartupFailure() }
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        /// Reports early helper exit without trusting a different process on the port.
        var isRunning: Bool {
            #if DEBUG
                if Self.isUITest, ProcessInfo.processInfo.environment["UNARU_TEST_BACKEND_ADDRESS"] != nil {
                    return true
                }
            #endif
            return process?.isRunning == true
        }

        /// Stops only this app's child, releasing its callback listener before a retry.
        func stop() {
            launchID = UUID()
            output?.fileHandleForReading.readabilityHandler = nil
            output = nil
            ready = false
            outputBuffer = Data()
            try? lifetime?.fileHandleForWriting.close()
            lifetime = nil
            if let process, process.isRunning {
                process.terminate()
                // Reaping also prevents a retry from racing the old listener.
                process.waitUntilExit()
            }
            process = nil
        }

        /// Opens the configuration directory so the owner can edit Kite credentials.
        func openConfiguration() {
            NSWorkspace.shared.activateFileViewerSelecting([Self.configurationDirectory.appendingPathComponent(".env")])
        }

        /// Startup errors never expose process environment or credential values.
        struct StartupFailure: Error {}
    }
#endif
