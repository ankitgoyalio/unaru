//
//  ControlledBackend.swift
//  unaru
//
//  Created by Ankit Goyal on 01/11/2026.

#if os(macOS)
    import Foundation
    import Network

    /// A real loopback HTTP server owned by each UI test, with no broker dependency.
    final class ControlledBackend: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "unaru.ui-test-backend")
        private let lock = NSLock()
        private var responses: [String: (status: Int, hold: Bool, body: String?)] = [:]
        private var authenticated = false
        private var profileRequests = 0
        private var responseStatus = 200
        private var holdResponses = false
        private var heldResponses: [@Sendable () -> Void] = []
        private var responseBody: String?
        private var responseLocation: String?
        private var requestCount = 0
        private var paths: [String] = []
        private var persistence: String?

        var requestedPaths: [String] {
            lock.withLock { paths }
        }

        func usePersistence(_ value: String?) {
            lock.withLock { persistence = value }
        }

        private var completedCount = 0
        private var loginResult = "pending"
        private var handoffs = 0
        private var logoutRequests = 0
        private var attemptNumber = 0
        private var profileJSON: String?
        private var avatar: String?

        func useProfile(_ json: String) {
            lock.withLock { profileJSON = json }
        }

        private func accountProfile(avatarField: String) -> String {
            lock.withLock {
                profileJSON ?? "{\"name\":\"Asha Rao\",\"userID\":\"AB1234\",\"email\":\"asha@example.invalid\",\"broker\":\"ZERODHA\",\"accountType\":\"individual\",\"exchanges\":[\"NSE\",\"BSE\"],\"products\":[\"CNC\",\"MIS\"],\"orderTypes\":[\"LIMIT\",\"SL-M\"]\(avatarField)}"
            }
        }

        private var handoffURL: String?

        var browserURL: String? {
            lock.withLock { handoffURL }
        }

        func finishLogin(state: String) {
            lock.withLock { loginResult = state }
        }

        func useAvatar(_ url: String) {
            lock.withLock { avatar = url }
        }

        var browserHandoffs: Int {
            lock.withLock { handoffs }
        }

        func completeLogin() {
            lock.withLock {
                loginResult = "signedIn"
                authenticated = true
            }
        }

        func loseSession() {
            lock.withLock { authenticated = false }
        }

        var validations: Int {
            lock.withLock { profileRequests }
        }

        var logouts: Int {
            lock.withLock { logoutRequests }
        }

        var loginAttempts: Int {
            lock.withLock { attemptNumber }
        }

        func respond(path: String, status: Int, hold: Bool = false, body: String? = nil) {
            lock.withLock { responses[path] = (status, hold, body) }
        }

        var address: String {
            "http://127.0.0.1:\(listener.port!.rawValue)"
        }

        var requests: Int {
            lock.withLock { requestCount }
        }

        var pendingResponses: Int {
            lock.withLock { heldResponses.count }
        }

        var completedResponses: Int {
            lock.withLock { completedCount }
        }

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed: ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: queue)
                receive(connection, accumulated: Data())
            }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 5) == .success, case .ready = listener.state, (listener.port?.rawValue ?? 0) != 0 else {
                listener.cancel()
                throw NSError(domain: "ControlledBackend", code: 1)
            }
        }

        func respond(status: Int, hold: Bool = false, body: String? = nil, location: String? = nil) {
            lock.withLock {
                responseStatus = status
                holdResponses = hold
                responseBody = body
                responseLocation = location
            }
        }

        func releaseResponses() {
            let pending = lock.withLock {
                holdResponses = false
                let pending = heldResponses
                heldResponses.removeAll()
                return pending
            }
            for response in pending {
                queue.async(execute: response)
            }
        }

        func stop() {
            listener.cancel()
            releaseResponses()
        }

        private func receive(_ connection: NWConnection, accumulated: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
                guard let self else { return }
                let request = accumulated + (data ?? Data())
                guard request.count <= 8192, error == nil else {
                    connection.cancel()
                    return
                }
                guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if complete {
                        connection.cancel()
                    } else {
                        receive(connection, accumulated: request)
                    }
                    return
                }
                let headerEnd = text.range(of: "\r\n\r\n")!
                let headerLines = String(text[..<headerEnd.lowerBound]).components(separatedBy: "\r\n")
                let contentLength = headerLines.first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                let requestBody = Data(text[headerEnd.upperBound...].utf8)
                guard requestBody.count >= contentLength else {
                    if complete {
                        connection.cancel()
                    } else {
                        receive(connection, accumulated: request)
                    }
                    return
                }
                let lines = text.components(separatedBy: "\r\n")
                let path = lines[0].split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let (configuredStatus, hold, configuredBody, location, signedIn) = lock.withLock {
                    requestCount += 1
                    paths.append(path)
                    if path == "/profile" {
                        profileRequests += 1
                    }
                    let override = responses[path]
                    return (override?.status ?? responseStatus, override?.hold ?? holdResponses,
                            override?.body ?? responseBody, responseLocation, authenticated)
                }
                let authorized = lines.contains { $0.lowercased() == "authorization: bearer ui-test-token" }
                let status = authorized ? configuredStatus : 401
                let persistenceField = lock.withLock { persistence.map { ",\"persistence\":\"\($0)\"" } ?? "" }
                let body: String
                if path == "/logout", text.hasPrefix("POST") {
                    lock.withLock {
                        logoutRequests += 1
                        if status == 200 {
                            authenticated = false
                            loginResult = "failed"
                        }
                    }
                    body = configuredBody ?? #"{"revocation":"confirmed"}"#
                } else if path == "/login", text.hasPrefix("POST") {
                    let number = lock.withLock {
                        loginResult = "pending"
                        authenticated = false
                        attemptNumber += 1
                        return attemptNumber
                    }
                    body = "{\"id\":\"ui-attempt-\(number)\",\"browserURL\":\"https://kite.zerodha.com/connect/login?v=3&api_key=test-key&redirect_params=state%3Dtest-state\",\"expiresAt\":2000000000}"
                } else if path == "/test/browser" {
                    let payload = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
                    let url = payload?["browserURL"] as? String
                    lock.withLock {
                        handoffs += 1
                        handoffURL = url
                    }
                    body = "{}"
                } else if path.hasPrefix("/login/ui-attempt-"), text.hasPrefix("DELETE") {
                    lock.withLock {
                        if path == "/login/ui-attempt-\(attemptNumber)", status == 200 {
                            loginResult = "failed"
                            authenticated = false
                        }
                    }
                    body = "{}"
                } else if path.hasPrefix("/login/ui-attempt-") {
                    let (result, avatar) = lock.withLock {
                        (path == "/login/ui-attempt-\(attemptNumber)" ? loginResult : "failed", avatar)
                    }
                    let avatarField = avatar.map { ",\"avatarURL\":\"\($0)\"" } ?? ""
                    body = configuredBody ?? (result == "signedIn"
                        ? "{\"state\":\"signedIn\",\"profile\":\(accountProfile(avatarField: avatarField))\(persistenceField)}"
                        : "{\"state\":\"\(result)\"}")
                } else if path == "/portfolio/positions" {
                    body = configuredBody ?? #"{"positions":[],"retrievedAt":815000000}"#
                } else if path == "/portfolio/holdings" || path == "/portfolio/mutual-funds" {
                    body = configuredBody ?? #"{"holdings":[],"retrievedAt":815000000}"#
                } else if path == "/portfolio/funds" {
                    body = configuredBody ?? #"{"segments":[],"retrievedAt":815000000}"#
                } else if path == "/profile" {
                    let avatarField = lock.withLock { avatar.map { ",\"avatarURL\":\"\($0)\"" } ?? "" }
                    body = configuredBody ?? accountProfile(avatarField: avatarField)
                } else {
                    body = configuredBody ?? (status == 200 ? "{\"state\":\"\(signedIn ? "signedIn" : "signedOut")\"\(persistenceField)}" : "{}")
                }
                let locationHeader = location.map { "Location: \($0)\r\n" } ?? ""
                let response = "HTTP/1.1 \(status) Response\r\n\(locationHeader)Content-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                let send: @Sendable () -> Void = { [self] in
                    lock.withLock { completedCount += 1 }
                    if status == 0 {
                        connection.cancel()
                        return
                    }
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
                if hold {
                    lock.withLock { heldResponses.append(send) }
                } else {
                    send()
                }
            }
        }
    }
#endif
