//
//  BoundedRevocation.swift
//  unaru
//
//  Created by Ankit Goyal on 03/11/2026.

import KiteConnect

/// Races the external operation against a deadline without waiting for a transport
/// that ignores cancellation. Late responses have no backend authority to mutate.
actor BoundedRevocation {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var request: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    /// Returns the positive provider result, or false when the deadline wins.
    func run(client: KiteClient, timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            request = Task {
                let confirmed = await (try? client.invalidateSession()) == true
                finish(confirmed)
            }
            deadline = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                finish(false)
            }
        }
    }

    private func finish(_ confirmed: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        request?.cancel()
        deadline?.cancel()
        request = nil
        deadline = nil
        continuation.resume(returning: confirmed)
    }
}
