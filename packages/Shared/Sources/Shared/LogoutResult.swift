/// The outcome of a local logout, without disclosing Kite credentials.
public struct LogoutResult: Codable, Sendable {
    /// Only a positive Kite response confirms remote token invalidation.
    public enum Revocation: String, Codable, Sendable {
        case confirmed
        case unconfirmed
    }

    /// Local authority is always cleared, independently of this remote outcome.
    public let revocation: Revocation

    public init(revocation: Revocation) {
        self.revocation = revocation
    }
}
