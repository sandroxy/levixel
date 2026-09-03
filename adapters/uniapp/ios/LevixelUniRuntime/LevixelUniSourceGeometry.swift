import CoreGraphics

enum LevixelUniSourceGeometry {
    static func positiveIntersection(_ first: CGRect, _ second: CGRect) -> CGRect? {
        guard isFiniteNonEmpty(first), isFiniteNonEmpty(second) else { return nil }
        let intersection = first.intersection(second)
        return isFiniteNonEmpty(intersection) ? intersection : nil
    }

    private static func isFiniteNonEmpty(_ rect: CGRect) -> Bool {
        rect.minX.isFinite
            && rect.minY.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.width > 0
            && rect.height > 0
    }
}
