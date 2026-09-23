import SwiftUI
import DisputeCore

/// One place for colour, shape and feedback, so the app reads as a single thing.
///
/// Warm paper and ink rather than the default blue-on-white: a notebook you'd
/// think in, not a form you'd fill in.
///
/// **Rust leads, verdigris supports.** This has now been both ways round, and
/// the reason it came back is worth writing down, because the objection to rust
/// was real and it was not wrong — it was about the wrong rust.
///
/// The complaint was that rust is a hot colour: it reads as alert, as the thing
/// you press when something has gone wrong, so an app about two people arguing
/// was also shouting at them from every primary button. That is true of a bright
/// red-orange. It is not true of *iron oxide* — the colour of a rusted hinge or
/// a terracotta pot, which is dark, brown and completely calm. Verdigris and
/// rust are the same story told twice anyway: both are what a metal becomes when
/// it is left alone for years. One is what copper does, the other is what iron
/// does, and neither of them is in a hurry.
///
/// So the house colour is the brown end of rust, deep enough to carry white text
/// with room to spare and dull enough that a screen full of it reads as a
/// notebook rather than a warning. Verdigris keeps the complementary jobs, where
/// a cool colour against warm paper is exactly right.
///
/// **What this forced.** Rust cannot be the house colour and the alarm at the
/// same time — a colour used for emphasis cannot also be used for alarm, which
/// is the rule that got the app here in the first place. So `alert` moved to
/// oxblood: redder, more saturated, no brown in it. Against the house rust it is
/// unmistakably the hotter of the two, and it still only ever appears on a screen
/// that has already said "didn't work" in words.
enum Theme {
    /// Light and dark values for the same role, resolved by the system.
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Warm paper, not white.
    static let background = adaptive(light: (0.96, 0.94, 0.89), dark: (0.11, 0.10, 0.09))
    /// Cards sit slightly above the page.
    static let surface = adaptive(light: (0.99, 0.97, 0.93), dark: (0.16, 0.15, 0.13))
    static let ink = adaptive(light: (0.15, 0.13, 0.11), dark: (0.94, 0.92, 0.87))
    static let hairline = adaptive(light: (0.80, 0.74, 0.64), dark: (0.32, 0.29, 0.25))

    /// The house colour. The main action, and anything the app is confident about.
    ///
    /// Iron oxide at the brown end — a rusted hinge, a terracotta pot, the red
    /// of an old barn. Not the orange-red of a warning triangle, which is a
    /// different colour doing a different job three properties down.
    ///
    /// 7.2:1 against white, so the primary button carries its label with room to
    /// spare, and 6.3:1 as text on the paper background. Lifted in dark mode,
    /// where it cannot go deeper and still be seen.
    static let brand = adaptive(light: (0.55, 0.27, 0.15), dark: (0.85, 0.50, 0.34))

    /// The same colour at the weight a background wants, for tints and fills that
    /// would be shouting at full strength.
    static let brandSoft = adaptive(light: (0.97, 0.91, 0.86), dark: (0.24, 0.16, 0.12))

    /// The complementary colour. Everything that wants to be noticed without
    /// being worried about.
    ///
    /// Brass, and it stayed brass when the house colour changed under it, which
    /// took some arguing with.
    ///
    /// The case against was that gold beside rust is two warm colours competing.
    /// The case for is everything this colour actually has to do: it is one
    /// side's colour on the agreement meter, opposite sage, and it is the half of
    /// that meter showing what the two of them still disagree about. Verdigris —
    /// the obvious swap, now that it is free — would have put two greens either
    /// side of that bar, and a meter whose halves are both green is a meter
    /// nobody can read at a glance while passing a phone across a table.
    ///
    /// Brass against rust is fine in practice because they are not the same kind
    /// of warm: this is a dark yellow with no red in it, against a red-brown with
    /// no yellow. What matters is that neither of them is ever the primary button
    /// and one of somebody's own colours at the same time, which is the mistake
    /// that got made twice already.
    ///
    /// Deep enough to carry caption-sized text on the light background, which is
    /// what rules out the brighter golds. A yellow that looks best as a large
    /// fill is a yellow that fails on the 11pt label under it.
    static let accent = adaptive(light: (0.56, 0.40, 0.05), dark: (0.93, 0.77, 0.38))

    /// Something has gone wrong. Nothing else.
    ///
    /// Oxblood, and this is its third address. It was iron oxide, which stopped
    /// being available the moment iron oxide became the house colour — a colour
    /// used for emphasis cannot also be used for alarm, and that rule does not
    /// care which direction the collision came from.
    ///
    /// The move is small and deliberate: redder, more saturated, no brown left in
    /// it. Next to the house rust it reads as the hotter of the two, which is the
    /// only comparison that has to work, because this colour never appears except
    /// on a screen that has already said "didn't work" in words and drawn a
    /// triangle next to it.
    static let alert = adaptive(light: (0.63, 0.13, 0.19), dark: (0.88, 0.38, 0.42))

    /// Anything to do with the AI.
    ///
    /// Kept as a name of its own even though it now resolves to the house colour.
    /// The AI is no longer a side offer bolted onto the app — it writes the list,
    /// names the crux and finds the assumptions — so a separate colour for it was
    /// drawing a line the app no longer has. Left as an alias rather than deleted
    /// because "this bit is the AI" is still a thing the views want to say, and
    /// the day it needs its own colour again this is where that goes.
    static var assist: Color { brand }

    /// Each side gets a colour. Brass and ink-blue, never red and green — no
    /// side should look like the right one or the wrong one.
    ///
    /// Neither is the house colour and neither is the alert colour, and that
    /// invariant is the whole point of this function. Party A was rust while rust
    /// was every button, so A's colour read as the app agreeing with A; then rust
    /// became the alert colour, so A's colour read as the app flagging A. Rust is
    /// the house colour again now, which is exactly why A is not going back to
    /// it. Brass and ink-blue sit warm against cool with nothing implied about
    /// either.
    static func color(for party: Party) -> Color {
        switch party {
        case .a: accent
        case .b: adaptive(light: (0.22, 0.33, 0.42), dark: (0.47, 0.63, 0.74))
        }
    }

    /// Common ground, and anything settled. Sage.
    ///
    /// It was a leaf green, which is a *fresh* colour — the green of a tick in a
    /// checkout flow, saying "that worked". What this colour marks is two people
    /// finding they already agreed about most of it, which is not a success
    /// notification; it is the calm part of the screen, and the one the app wants
    /// them to sit with. Sage is that green with the brightness taken out of it:
    /// grey enough to belong on tan paper next to verdigris and brass, still
    /// unmistakably green where it matters, which is the filled half of the
    /// agreement meter.
    ///
    /// Held at 4.6:1 on the light background, because this is text as well as
    /// fill — "Key saved" in Settings is drawn in it. Any greyer and it starts
    /// failing that; any deeper and it stops being sage.
    static let agree = adaptive(light: (0.36, 0.45, 0.33), dark: (0.64, 0.74, 0.58))

    /// A note in the margin, not an alarm — which is exactly what the complement
    /// is for, so it is the complement.
    ///
    /// Kept as its own name because "this wants a second look" is a thing the
    /// views want to say, and the day it needs a hue of its own this is where
    /// that goes. What it must never quietly become again is the alert colour:
    /// the assumptions card is the one screen where the app says something about
    /// a person's own words back to them, and drawing it in warning red would
    /// undo every careful sentence on it.
    static var caution: Color { accent }

    /// Where the two of them differ. Emphasis, never alarm — see `alert`.
    static var disagree: Color { accent }

    static let cardCorner: CGFloat = 14
    static let screenPadding: CGFloat = 22
}

// MARK: - Feedback

/// Physical feedback for anything that commits.
///
/// Deliberately sparse: ticking a box and finishing a turn get a tap, and the
/// crux reveal gets a single heavier one. Anything more and it stops meaning
/// something.
enum Haptics {
    /// Whether the person wants any of this.
    ///
    /// Settings has had a "Haptics" switch since the settings screen existed and
    /// nothing ever read it, so turning it off changed nothing — the one kind of
    /// bug nobody reports, because from the outside it looks the same as the
    /// feature just not being very noticeable.
    ///
    /// Read fresh each time rather than cached: it is one `UserDefaults` lookup
    /// against a tap, and caching it would mean the switch only took effect on
    /// the next launch.
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    /// One generator per style, kept alive rather than built per tap.
    ///
    /// A generator that was created a moment ago has to wake the Taptic Engine
    /// before it can play anything. That costs tens of milliseconds and, worse,
    /// a different number of them each time — so a tap meant to land with
    /// something on screen lands slightly late, by an amount that varies. Held
    /// and prepared, it fires when it is told to.
    ///
    /// This is also most of what "stronger" turns out to mean. The amplitude of
    /// an impact is fixed by its style — `impactOccurred()` is already full
    /// intensity — so a tap cannot be turned up past `.heavy`. What it can be is
    /// on time and sharp-edged, and a cold generator is neither.
    @MainActor
    private static var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    @MainActor
    private static func generator(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        if let existing = generators[style] { return existing }
        let made = UIImpactFeedbackGenerator(style: style)
        generators[style] = made
        return made
    }

    /// Warms the engine for a tap that is coming but has not happened yet.
    ///
    /// Worth calling only when the moment is known in advance — the gavel starts
    /// its lift a fixed time before it lands, so it can say so. Preparing
    /// keeps the engine awake for a second or so and is a no-op if it already is.
    @MainActor
    static func prepare(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        generator(style).prepare()
    }

    @MainActor
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        generator(style).impactOccurred()
    }

    @MainActor
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Not gated on the switch. These mark something having gone wrong or having
    /// been decided, and they are the two moments where the phone is face-down
    /// on a table being passed between two people — the only channel left.
    @MainActor
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
