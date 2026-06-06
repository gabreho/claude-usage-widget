import XCTest
@testable import ClaudeUsageKit

final class OAuthAuthorizationSessionTests: XCTestCase {
    func testCodexAuthorizationURLDoesNotIncludeStateParameter() throws {
        let session = UsageService.createOAuthAuthorizationSession(provider: .codex)
        let components = try XCTUnwrap(URLComponents(url: session.authorizationURL, resolvingAgainstBaseURL: false))
        let queryNames = Set((components.queryItems ?? []).map(\.name))

        XCTAssertNil(session.state)
        XCTAssertFalse(queryNames.contains("state"))
        XCTAssertTrue(queryNames.contains("codex_cli_simplified_flow"))
    }

    func testClaudeAuthorizationURLIncludesStateParameter() throws {
        let session = UsageService.createOAuthAuthorizationSession(provider: .claude)
        let components = try XCTUnwrap(URLComponents(url: session.authorizationURL, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let stateValue = try XCTUnwrap(queryItems.first(where: { $0.name == "state" })?.value)

        XCTAssertEqual(stateValue, session.state)
        XCTAssertFalse(stateValue.isEmpty)
    }
}
