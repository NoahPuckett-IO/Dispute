#if DEBUG
import Foundation

/// The whole session as one plain-text file: what the two people wrote, what the
/// app made of it, and every prompt and raw answer that passed between them.
///
/// Debug builds only. `ArgumentRecap.transcript` is the one people keep, and it
/// is deliberately the record of an argument rather than a record of the app.
/// This is the opposite: it is for reading the prompting, so it keeps the parts
/// that are of no interest to anyone in an argument and every part that shows
/// whether the model did its job. Nothing in it is shown in a shipped build.
public enum DebugTranscript {

    /// - Parameters:
    ///   - engine: which engine actually ran, as the app describes it.
    ///   - device: phone, OS, build. Written by the app layer, which is the only
    ///     part that can ask.
    public static func text(
        for dispute: Dispute,
        engine: String,
        device: String,
        entries: [PromptLog.Entry] = PromptLog.shared.entries
    ) -> String {
        var blocks: [String] = []

        blocks.append(
            """
            DISPUTE DEBUG TRANSCRIPT
            Taken: \(Date().formatted(date: .abbreviated, time: .standard))
            Device: \(device)
            Engine: \(engine)
            Mode: \(dispute.mode == .assisted ? "assisted" : "by hand")
            Stage reached: \(dispute.stage.rawValue)
            """
        )

        blocks.append(session(dispute))
        blocks.append(model(entries))

        return blocks.joined(separator: "\n\n")
    }

    // MARK: - What the two of them did

    private static func session(_ dispute: Dispute) -> String {
        var lines: [String] = ["SESSION", ""]

        lines.append("Title: \(dispute.title.isEmpty ? "(none)" : dispute.title)")
        lines.append("A: \(dispute.name(for: .a))")
        lines.append("B: \(dispute.name(for: .b))")

        for party in Party.allCases {
            let label = party == .a ? "A" : "B"
            lines.append("")
            lines.append("Position \(label):")
            lines.append(indent(dispute.positions[party], or: "(nothing written)"))

            let points = dispute.points(for: party)
            if !points.isEmpty {
                lines.append("Points \(label) wrote by hand:")
                lines.append(contentsOf: points.map { "    - \($0)" })
            }
        }

        lines.append("")
        lines.append("Claims (\(dispute.claims.count)):")
        if dispute.claims.isEmpty {
            lines.append("    (none built yet)")
        } else {
            for (index, claim) in dispute.claims.enumerated() {
                // Origin is on every row because a list that is all one person's
                // points is a breakdown fault, and it is invisible without this.
                lines.append(
                    "    \(index + 1). [from \(claim.origin == .a ? "A" : "B")] "
                        + "[A: \(tick(claim.agreement.a)) B: \(tick(claim.agreement.b))]"
                        + "\(claim.isContested ? " [SPLIT]" : "") \(claim.text)"
                )
            }
            lines.append("")
            lines.append(
                "Agreed on \(dispute.sharedClaims.count), split on \(dispute.contestedClaims.count)."
            )
        }

        if !dispute.assumptionFlags.isEmpty {
            lines.append("")
            lines.append("Assumptions flagged (\(dispute.assumptionFlags.count)):")
            for flag in dispute.assumptionFlags {
                lines.append(
                    "    [\(flag.party == .a ? "A" : "B")] \"\(flag.quote)\" -> \(flag.assumption)"
                )
            }
        }

        for party in Party.allCases {
            guard let rethink = dispute.rethinks[party] else { continue }
            let label = party == .a ? "A" : "B"
            let about = dispute.claim(withID: rethink.claimID)?.text ?? "(claim not found)"
            lines.append("")
            lines.append("Second look \(label):")
            lines.append("    Point they rejected: \(about)")
            lines.append("    Best case for it: \(rethink.bestCase)")
            lines.append("    What would change their mind: \(rethink.changeCondition)")
        }

        lines.append("")
        if let crux = dispute.crux {
            lines.append("Crux shown: \(crux.question)")
            lines.append("    A lands: \(crux.positions.a)")
            lines.append("    B lands: \(crux.positions.b)")
            lines.append("    Needs conversation: \(crux.needsConversation)")
            lines.append("    Usable by the app's own test: \(crux.isUsable)")
        } else {
            lines.append("Crux shown: (none)")
        }

        lines.append("")
        lines.append("Write-up shown:")
        lines.append(indent(dispute.recap, or: "(not written yet)"))

        return lines.joined(separator: "\n")
    }

    private static func tick(_ answer: Bool?) -> String {
        switch answer {
        case true: "yes"
        case false: "no"
        case nil: "-"
        }
    }

    // MARK: - What the model was asked, and said

    private static func model(_ entries: [PromptLog.Entry]) -> String {
        var lines = ["WHAT THE MODEL WAS ASKED", ""]

        guard !entries.isEmpty else {
            lines.append(
                "Nothing was recorded. Either this session ran by hand, or it "
                    + "resumed from a saved argument whose model calls happened "
                    + "in an earlier launch."
            )
            return lines.joined(separator: "\n")
        }

        // The system prompt is the same on every call, so it goes in once. It is
        // long, and repeating it six times buries the part that differs.
        if let system = entries.compactMap({ entry -> String? in
            if case let .call(call) = entry { return call.system }
            return nil
        }).first {
            lines.append("System prompt, sent with every call:")
            lines.append(indent(system, or: "(none)"))
            lines.append("")
        }

        // Numbered by call rather than by entry, so the notes in between don't
        // leave gaps that read as a call having gone missing.
        var number = 0
        for entry in entries {
            switch entry {
            case let .note(note):
                lines.append("NOTE: \(note.text)")
                lines.append("")

            case let .call(call):
                number += 1
                lines.append(String(repeating: "-", count: 60))
                lines.append(
                    "CALL \(number): \(call.step)  "
                        + "[\(call.engine), \(String(format: "%.1f", call.seconds))s]"
                )
                if let system = otherSystemPrompt(call, entries: entries) {
                    lines.append("This call used a different system prompt:")
                    lines.append(indent(system, or: "(none)"))
                }
                lines.append("")
                lines.append("PROMPT:")
                lines.append(indent(call.prompt, or: "(empty)"))
                lines.append("")
                if let failure = call.failure {
                    lines.append("FAILED: \(failure)")
                    if let reply = call.reply, !reply.isEmpty {
                        lines.append("PARTIAL ANSWER:")
                        lines.append(indent(reply, or: ""))
                    }
                } else {
                    lines.append("RAW ANSWER:")
                    lines.append(indent(call.reply ?? "", or: "(nothing came back)"))
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Nil when this call used the same system prompt as the first one, which is
    /// the normal case and already printed above.
    private static func otherSystemPrompt(_ call: PromptLog.Call, entries: [PromptLog.Entry]) -> String? {
        let first = entries.compactMap { entry -> String? in
            if case let .call(call) = entry { return call.system }
            return nil
        }.first
        return call.system == first ? nil : call.system
    }

    private static func indent(_ text: String, or placeholder: String) -> String {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return placeholder.isEmpty ? "" : "    \(placeholder)" }
        return trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
    }
}
#endif
