/// The backend's current Kite authentication status, disclosed only to authorized clients.
public struct SessionStatus: Codable, Sendable {
    /// The Kite session state. Additional states accompany future authentication support.
    public enum State: String, Codable, Sendable {
        /// The backend has no authenticated Kite session.
        case signedOut
        /// The backend has completed Kite authentication and profile retrieval.
        case signedIn
    }

    /// The current authentication state.
    public let state: State

    /// Creates a session-status response without broker credentials.
    public init(state: State) {
        self.state = state
    }
}
