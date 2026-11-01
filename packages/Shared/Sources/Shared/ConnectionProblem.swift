/// A machine-readable recovery category without credential or provider diagnostics.
public struct ConnectionProblem: Codable, Sendable {
    /// The supported recovery codes.
    public enum Code: String, Codable, Sendable {
        /// The server administrator has not supplied a valid connection token.
        case backendNotConfigured
        /// The authorized backend has no valid Kite session.
        case kiteSignInRequired
    }

    /// The corrective category without credential values.
    public let code: Code

    /// Creates a credential-free recovery response.
    public init(code: Code) {
        self.code = code
    }
}
