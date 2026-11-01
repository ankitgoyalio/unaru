// Generated from DocC examples. Run Scripts/check-documentation-examples.py --write.
import Testing
import KiteConnect

@Test func documentationExample0() async throws {
    let configuration = try KiteConfiguration()
    let client = try KiteClient(apiKey: "documentation-api-key", configuration: configuration)
    _ = client
}
