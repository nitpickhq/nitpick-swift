import Foundation

/// One value per owner (a window scene), found by the identity of the owner.
///
/// The owner is held weakly, and a found entry counts only when its owner is the very object that is asked for:
/// an `ObjectIdentifier` can be given to a new object once the old one is gone, and then the old entry
/// (a window without a scene) must not be used for the new owner. A discarded value goes to `onDiscard`,
/// so the caller can hide the window or end the registration that belongs to it.
@MainActor
final class SceneTable<Owner: AnyObject, Value> {
    struct Entry {
        weak var owner: Owner?
        var value: Value
    }

    /// Internal so a test can put an entry under the identifier of another owner, the way a reused address would.
    var entries: [ObjectIdentifier: Entry] = [:]
    var onDiscard: (Value) -> Void

    init(onDiscard: @escaping (Value) -> Void = { _ in }) {
        self.onDiscard = onDiscard
    }

    var count: Int { entries.count }
    var values: [Value] { entries.values.map(\.value) }

    /// The value of this owner. An entry under the same identifier that belongs to another (or no) owner is discarded.
    func value(for owner: Owner) -> Value? {
        let key = ObjectIdentifier(owner)
        guard let entry = entries[key] else { return nil }
        if entry.owner === owner { return entry.value }
        entries[key] = nil
        onDiscard(entry.value)
        return nil
    }

    func set(_ value: Value, for owner: Owner) {
        let key = ObjectIdentifier(owner)
        if let old = entries[key], old.owner !== owner { onDiscard(old.value) }
        entries[key] = Entry(owner: owner, value: value)
    }

    /// The owner is gone (a scene that disconnected): the value is discarded.
    func remove(_ owner: Owner) {
        guard let entry = entries.removeValue(forKey: ObjectIdentifier(owner)) else { return }
        onDiscard(entry.value)
    }

    /// Discards every entry whose owner no longer exists.
    func prune() {
        for (key, entry) in entries where entry.owner == nil {
            entries[key] = nil
            onDiscard(entry.value)
        }
    }

    func removeAll() {
        let all = entries.values.map(\.value)
        entries = [:]
        for value in all { onDiscard(value) }
    }
}
