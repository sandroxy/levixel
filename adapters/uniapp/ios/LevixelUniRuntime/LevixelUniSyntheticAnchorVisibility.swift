import Foundation

enum LevixelUniSyntheticAnchorVisibility {
    // Levixel rejects sources whose ancestors are transparent. Keep the host
    // eligible for registry lookup and hide each synthetic anchor itself.
    static let hostAlpha: CGFloat = 1
    static let anchorAlpha: CGFloat = 0
}
