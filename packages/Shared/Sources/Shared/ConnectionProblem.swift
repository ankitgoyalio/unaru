/// A machine-readable backend configuration failure, separate from Kite authentication.
public struct ConnectionProblem: Codable, Sendable {
    /// The supported configuration-failure codes.
    public enum Code: String, Codable, Sendable {
        /// The server administrator has not supplied a valid connection token.
        case backendNotConfigured
    }

    /// The corrective category without credential values.
    public let code: Code

    /// Creates a credential-free configuration error response.
    public init(code: Code) {
        self.code = code
    }
}
