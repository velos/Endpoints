import Foundation

/// A one-shot latch: `wait()` suspends until some other task calls `open()`.
///
/// Lives outside the Apple-platform-gated test transport because tests that run on
/// every platform use it too.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isOpened: Bool { isOpen }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

extension Gate {
    /// Waits up to `nanoseconds` for the gate to open, returning whether it did.
    ///
    /// Use this when a test asserts that something *will* happen: an unbounded `wait()`
    /// would hang the suite instead of failing when the behavior regresses.
    nonisolated func wait(upTo nanoseconds: UInt64) async -> Bool {
        let pollInterval: UInt64 = 25_000_000
        var elapsed: UInt64 = 0

        while elapsed < nanoseconds {
            if await isOpened { return true }
            try? await Task.sleep(nanoseconds: pollInterval)
            elapsed += pollInterval
        }

        return await isOpened
    }
}
