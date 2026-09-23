import XCTest
@testable import DisputeCore

/// The eight tuning debates, against the real model.
///
///     MISTRAL_API_KEY=… swift test --filter FixtureScoring
///
/// `Fixtures/debates.json` has been the answer key for crux detection since the
/// on-device days, and until now there was nothing in the repository that read
/// it. It was run by hand, which is why `docs/DECISIONS.md` can say Qwen3 1.7B
/// matched on seven of eight and cannot say what anything since has done.
///
/// This is not a pass/fail test and must not become one. What it asserts is
/// mechanical — a crux came back, and enough claims survived the filter to build
/// one from — because the thing actually being measured is whether the crux
/// matches `expectedCrux` *in substance*, and no assertion can read that. It
/// prints both, side by side, for somebody to read.
///
/// It runs the real pipeline rather than the crux prompt alone: claims are
/// generated, deduplicated and filtered exactly as a session would, then ticked,
/// then handed to `findCrux`. That is deliberate. The claim filter is upstream of
/// the crux and can starve it — a session in August 2026 cut six good claims to
/// two and the crux was then drawn from two sentences the two people had typed
/// themselves. A harness that skipped that step would have scored that session as
/// fine.
final class FixtureScoringTests: XCTestCase {
    private struct Debate: Decodable {
        let topic: String
        let sideA: String
        let sideB: String
        let expectedCrux: String
    }

    private struct Fixtures: Decodable {
        let debates: [Debate]
    }

    private var engine: CloudEngine!

    override func setUpWithError() throws {
        guard let key = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"],
              !key.trimmed.isEmpty
        else {
            throw XCTSkip("set MISTRAL_API_KEY to score the fixtures")
        }
        engine = CloudEngine(apiKey: key)
    }

    /// `Fixtures/` sits beside the package rather than inside it, so it is found
    /// by walking up from this file rather than by `Bundle.module` — which would
    /// mean copying the answer key into the package's resources and having two of
    /// them.
    private func fixtures() throws -> [Debate] {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            directory.deleteLastPathComponent()
            let candidate = directory.appendingPathComponent("Fixtures/debates.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try JSONDecoder()
                    .decode(Fixtures.self, from: Data(contentsOf: candidate))
                    .debates
            }
        }
        throw XCTSkip("Fixtures/debates.json not found above \(#filePath)")
    }

    func testTheEightDebatesProduceCruxes() async throws {
        let debates = try fixtures()
        var produced = 0
        var report = "\n\n"

        for (index, debate) in debates.enumerated() {
            let number = index + 1
            report += "────────────────────────────────────────────────────────\n"
            report += "\(number). \(debate.topic)\n\n"

            var dispute = Dispute(
                title: debate.topic,
                mode: .assisted,
                names: PartyPair(a: "Person A", b: "Person B"),
                positions: PartyPair(a: debate.sideA, b: debate.sideB)
            )

            do {
                let claims = try await engine.breakDown(
                    positionA: debate.sideA,
                    positionB: debate.sideB,
                    disputeTitle: debate.topic
                )
                dispute.claims = claims
                report += "   claims kept: \(claims.count)\n"
                for claim in claims {
                    report += "     [\(claim.origin == .a ? "A" : "B")] \(claim.text)\n"
                }

                // Each of them ticks their own side's points and crosses the
                // other's, which is the shape of a session that found no common
                // ground — the hardest input the crux call gets.
                for position in dispute.claims.indices {
                    let origin = dispute.claims[position].origin
                    dispute.claims[position].setAgreement(origin == .a, for: .a)
                    dispute.claims[position].setAgreement(origin == .b, for: .b)
                }

                if let crux = try await engine.findCrux(in: dispute) {
                    produced += 1
                    report += "\n   GOT      \(crux.question)\n"
                    report += "   EXPECTED \(debate.expectedCrux)\n"
                    report += "   test     \(crux.test)\n"
                } else {
                    report += "\n   GOT      (nothing usable)\n"
                    report += "   EXPECTED \(debate.expectedCrux)\n"
                }
            } catch {
                report += "   FAILED: \(error)\n"
            }

            // The free tier allows a request a second and this makes sixteen of
            // them. Slower than necessary is better than a run that reports a
            // model problem it caused itself.
            try await Task.sleep(for: .milliseconds(1200))
        }

        report += "────────────────────────────────────────────────────────\n"
        report += "Produced a crux on \(produced) of \(debates.count).\n"
        report += "Read them. Matching in substance is the measure, not matching in words.\n\n"
        print(report)

        // Mechanical only, deliberately. See the note on this class.
        XCTAssertEqual(
            produced,
            debates.count,
            "the pipeline failed to produce a crux on \(debates.count - produced) of them"
        )
    }
}
