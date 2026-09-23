import XCTest
@testable import DisputeCore

final class PartyTests: XCTestCase {
    func testOpponentIsTheOtherParty() {
        XCTAssertEqual(Party.a.opponent, .b)
        XCTAssertEqual(Party.b.opponent, .a)
    }

    func testOpponentIsItsOwnInverse() {
        XCTAssertEqual(Party.a.opponent.opponent, .a)
    }
}

final class PartyPairTests: XCTestCase {
    func testSubscriptReadsAndWritesEachSide() {
        var pair = PartyPair(both: "")
        pair[.a] = "left"
        pair[.b] = "right"

        XCTAssertEqual(pair.a, "left")
        XCTAssertEqual(pair.b, "right")
        XCTAssertEqual(pair[.a], "left")
        XCTAssertEqual(pair[.b], "right")
    }

    func testAllSatisfyRequiresBothSides() {
        XCTAssertTrue(PartyPair(a: "x", b: "y").allSatisfy { !$0.isEmpty })
        XCTAssertFalse(PartyPair(a: "x", b: "").allSatisfy { !$0.isEmpty })
    }

    /// The reason this type exists instead of `[Party: Value]`: Swift encodes
    /// dictionaries with enum keys as a flat alternating array, not an object.
    func testEncodesAsAJSONObject() throws {
        let data = try JSONEncoder().encode(PartyPair(a: "one", b: "two"))
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains("\"a\":\"one\""))
        XCTAssertTrue(text.contains("\"b\":\"two\""))
    }
}

final class SessionStageTests: XCTestCase {
    func testStagesAreOrdered() {
        XCTAssertLessThan(SessionStage.setup, SessionStage.summary)
        XCTAssertLessThan(SessionStage.positions, SessionStage.checklist)
    }

    func testEachStageAdvancesToTheNext() {
        XCTAssertEqual(SessionStage.setup.next, .positions)
        XCTAssertEqual(SessionStage.positions.next, .checklist)
        XCTAssertEqual(SessionStage.checklist.next, .crux)
        XCTAssertEqual(SessionStage.crux.next, .summary)
    }

    func testSummaryIsTerminal() {
        XCTAssertTrue(SessionStage.summary.isTerminal)
        XCTAssertNil(SessionStage.summary.next)
    }

    func testChainReachesEveryStageWithoutGaps() {
        var walked: [SessionStage] = [.setup]
        while let next = walked.last?.next { walked.append(next) }

        XCTAssertEqual(walked.count, SessionStage.allCases.count)
        XCTAssertEqual(walked.last, .summary)
    }

    /// Exactly two stages are taken in turns, so the phone changes hands twice.
    /// An earlier design had five and people gave up before the crux.
    func testExactlyTwoStagesAreTakenInTurns() {
        XCTAssertEqual(SessionStage.allCases.filter(\.isPerParty), [.positions, .checklist])
    }
}
