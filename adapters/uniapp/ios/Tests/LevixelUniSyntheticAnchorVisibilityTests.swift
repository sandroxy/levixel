import Foundation

@main
private enum LevixelUniSyntheticAnchorVisibilityTests {
    static func main() {
        precondition(
            LevixelUniSyntheticAnchorVisibility.hostAlpha > 0.01,
            "The synthetic anchor host must remain eligible for source registry lookup"
        )
        precondition(
            LevixelUniSyntheticAnchorVisibility.anchorAlpha <= 0.01,
            "Synthetic anchors must not render above the UniApp HTML source"
        )
    }
}
