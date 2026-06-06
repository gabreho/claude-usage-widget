import XCTest
@testable import ClaudeUsageKit

final class CodexUsageMappingTests: XCTestCase {
    private func decode(_ json: String) throws -> CodexUsageResponse {
        try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    }

    func testMapsPrimaryAndSecondaryWindows() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": 12.5, "resets_in_seconds": 3600, "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": 47.0, "resets_in_seconds": 86400, "limit_window_seconds": 604800 }
          }
        }
        """

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = try decode(json).toUsageResponse(now: now)

        XCTAssertEqual(usage.fiveHour.utilization, 12.5, accuracy: 0.001)
        XCTAssertEqual(usage.sevenDay.utilization, 47.0, accuracy: 0.001)

        // resets_in_seconds is projected onto an absolute reset date.
        let sessionReset = try XCTUnwrap(usage.fiveHour.resetDate)
        XCTAssertEqual(sessionReset.timeIntervalSince(now), 3600, accuracy: 1)

        let weeklyReset = try XCTUnwrap(usage.sevenDay.resetDate)
        XCTAssertEqual(weeklyReset.timeIntervalSince(now), 86400, accuracy: 1)

        // Codex does not populate the Claude-specific buckets.
        XCTAssertNil(usage.sevenDayOpus)
        XCTAssertNil(usage.sevenDaySonnet)
        XCTAssertNil(usage.extraUsage)
    }

    func testTopLevelWindowsWithoutRateLimitWrapper() throws {
        let json = """
        {
          "primary_window": { "used_percent": 5 },
          "secondary_window": { "used_percent": 60 }
        }
        """

        let usage = try decode(json).toUsageResponse()
        XCTAssertEqual(usage.fiveHour.utilization, 5, accuracy: 0.001)
        XCTAssertEqual(usage.sevenDay.utilization, 60, accuracy: 0.001)
        // No reset info supplied → no reset date.
        XCTAssertNil(usage.fiveHour.resetDate)
    }

    func testMissingWindowsYieldZeroedLanes() throws {
        let usage = try decode("{}").toUsageResponse()
        XCTAssertEqual(usage.fiveHour.utilization, 0)
        XCTAssertEqual(usage.sevenDay.utilization, 0)
        XCTAssertNil(usage.fiveHour.resetDate)
        XCTAssertNil(usage.sevenDay.resetDate)
    }

    func testToleratesNonArrayAdditionalRateLimits() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": 10, "resets_in_seconds": 600 }
          },
          "additional_rate_limits": "unexpected"
        }
        """

        let response = try decode(json)
        XCTAssertTrue(response.additionalRateLimits.isEmpty)
        XCTAssertEqual(response.toUsageResponse().fiveHour.utilization, 10, accuracy: 0.001)
    }

    func testDecodesAdditionalRateLimitsWhenPresent() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": 10 },
            "secondary_window": { "used_percent": 20 }
          },
          "additional_rate_limits": [
            { "id": "codex-spark", "title": "Codex Spark", "used_percent": 33.0, "resets_in_seconds": 1200 }
          ]
        }
        """

        let response = try decode(json)
        XCTAssertEqual(response.additionalRateLimits.count, 1)
        XCTAssertEqual(response.additionalRateLimits.first?.id, "codex-spark")
        XCTAssertEqual(response.additionalRateLimits.first?.title, "Codex Spark")
        XCTAssertEqual(response.additionalRateLimits.first?.usedPercent ?? 0, 33.0, accuracy: 0.001)
    }
}
