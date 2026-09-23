import XCTest
@testable import DisputeCore

final class DisputeStoreTests: XCTestCase {
    private var directory: URL!
    private var store: DisputeStore!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DisputeStoreTests-\(UUID().uuidString)")
        store = try DisputeStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testStartsEmpty() {
        XCTAssertFalse(store.hasSavedSession)
        XCTAssertNil(store.load())
    }

    func testASessionSurvivesSaveAndLoad() throws {
        var dispute = Dispute(
            title: "Nuclear power for climate change",
            names: PartyPair(a: "Alex", b: "Sam")
        )
        try dispute.advance()
        dispute.positions = PartyPair(
        a: "We need nuclear power because it is the only low carbon source that runs whatever the weather does.",
        b: "It is too slow to build and too costly, and the waste has nowhere settled to go."
    )

        try store.save(dispute)

        XCTAssertTrue(store.hasSavedSession)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored, dispute)
        XCTAssertEqual(restored.stage, .positions)
        XCTAssertEqual(restored.positions[.b], dispute.positions[.b])
        XCTAssertEqual(restored.name(for: .a), "Alex", "names survive a save")
    }

    func testSavingReplacesThePreviousSession() throws {
        try store.save(Dispute(title: "First"))
        try store.save(Dispute(title: "Second"))

        XCTAssertEqual(store.load()?.title, "Second")
    }

    func testDeleteEverythingLeavesNothingBehind() throws {
        try store.save(Dispute(title: "Whether to take the job"))
        XCTAssertTrue(store.hasSavedSession)

        try store.deleteEverything()

        XCTAssertFalse(store.hasSavedSession)
        XCTAssertNil(store.load())
    }

    func testDeletingWhenEmptyIsHarmless() {
        XCTAssertNoThrow(try store.deleteEverything())
    }

    /// A corrupt file should start a fresh session, not brick the app.
    func testCorruptDataReadsAsNoSession() throws {
        try store.save(Dispute(title: "Valid"))
        let file = directory.appendingPathComponent("session.json")
        try Data("not json".utf8).write(to: file)

        XCTAssertNil(store.load())
    }
}
