import Foundation

/// One of the two people in a dispute.
///
/// Deliberately not named — the app knows nothing about who these people are to
/// each other. Party A is whoever is holding the phone when the session starts.
public enum Party: String, Codable, Hashable, CaseIterable, Sendable {
    case a
    case b

    public var opponent: Party {
        switch self {
        case .a: .b
        case .b: .a
        }
    }
}

/// Exactly one `Value` per party.
///
/// Used instead of `[Party: Value]` for two reasons: a dictionary can be missing
/// a party at compile time, and Swift only encodes dictionaries as JSON objects
/// when the key is `String` or `Int` — a `String`-backed enum key silently
/// encodes as a flat alternating array instead.
public struct PartyPair<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var a: Value
    public var b: Value

    public init(a: Value, b: Value) {
        self.a = a
        self.b = b
    }

    public init(both value: Value) {
        self.a = value
        self.b = value
    }

    public subscript(party: Party) -> Value {
        get {
            switch party {
            case .a: a
            case .b: b
            }
        }
        set {
            switch party {
            case .a: a = newValue
            case .b: b = newValue
            }
        }
    }

    /// Both values, in a stable A-then-B order.
    public var values: [Value] { [a, b] }

    public func allSatisfy(_ predicate: (Value) -> Bool) -> Bool {
        predicate(a) && predicate(b)
    }
}
