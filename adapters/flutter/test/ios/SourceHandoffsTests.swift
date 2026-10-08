@main
private enum SourceHandoffsTests {
    static func main() {
        finishWithoutASourceDoesNotWait()
        finishBeforeVisibilityReplyWaitsForRestoration()
        finishWaitsForEveryRestoredSource()
        replacingAHandoffKeepsCleanupPending()
        lateRepliesCannotCompleteAnotherHandoff()
        removalOrDeactivationReleasesAllWaitersOnce()
        print("Passed 6 Flutter iOS source handoff tests.")
    }

    private static func finishWithoutASourceDoesNotWait() {
        let handoffs = SourceHandoffs()
        var finished = false
        handoffs.whenComplete { finished = true }
        precondition(finished, "A fade without a source must finish immediately")
    }

    private static func finishBeforeVisibilityReplyWaitsForRestoration() {
        let handoffs = SourceHandoffs()
        let restore = handoffs.begin()
        var removed = false
        // Dart can dispatch finish before the visibility channel reply, even
        // though both Dart handlers have awaited the same framework frame.
        handoffs.whenComplete { removed = true }
        precondition(!removed, "Cleanup must retain the preview during restoration")
        restore()
        precondition(removed, "Cleanup must complete when the preview is handed back")
    }

    private static func finishWaitsForEveryRestoredSource() {
        let handoffs = SourceHandoffs()
        let previousPage = handoffs.begin()
        let currentPage = handoffs.begin()
        var finished = false
        handoffs.whenComplete { finished = true }
        currentPage()
        precondition(!finished, "A previous page can still be restoring its source")
        previousPage()
        precondition(finished)
    }

    private static func replacingAHandoffKeepsCleanupPending() {
        let handoffs = SourceHandoffs()
        let old = handoffs.begin()
        var finished = false
        handoffs.whenComplete { finished = true }
        let replacement = handoffs.begin()
        old()
        precondition(!finished, "Superseding a visibility request must not release cleanup")
        replacement()
        precondition(finished)
    }

    private static func lateRepliesCannotCompleteAnotherHandoff() {
        let handoffs = SourceHandoffs()
        let old = handoffs.begin()
        old()
        let current = handoffs.begin()
        var finished = false
        handoffs.whenComplete { finished = true }
        old()
        precondition(!finished, "A duplicate reply must not consume another source's wait")
        current()
        precondition(finished)
    }

    private static func removalOrDeactivationReleasesAllWaitersOnce() {
        let handoffs = SourceHandoffs()
        let cancel = handoffs.begin()
        var finished = 0
        handoffs.whenComplete { finished += 1 }
        handoffs.whenComplete { finished += 1 }
        cancel()
        cancel()
        precondition(finished == 2, "Cleanup must drain exactly once when frames stop")
        handoffs.whenComplete { finished += 1 }
        precondition(finished == 3, "Canceled handoffs must not block future cleanup")
    }
}
