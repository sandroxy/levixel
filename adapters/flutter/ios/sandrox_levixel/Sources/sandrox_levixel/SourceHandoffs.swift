/// Keeps session cleanup behind every native-to-Flutter source restoration.
/// All calls run on the platform thread, including channel replies and frames.
final class SourceHandoffs {
    private var nextID = 0
    private var pending = Set<Int>()
    private var completions: [() -> Void] = []

    func begin() -> () -> Void {
        nextID += 1
        let id = nextID
        pending.insert(id)
        return { [weak self] in self?.complete(id) }
    }

    func whenComplete(_ completion: @escaping () -> Void) {
        guard !pending.isEmpty else { completion(); return }
        completions.append(completion)
    }

    private func complete(_ id: Int) {
        guard pending.remove(id) != nil, pending.isEmpty else { return }
        let callbacks = completions
        completions.removeAll()
        for callback in callbacks { callback() }
    }
}
