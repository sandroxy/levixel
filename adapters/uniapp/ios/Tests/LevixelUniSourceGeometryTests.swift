import CoreGraphics

@main
private enum LevixelUniSourceGeometryTests {
    static func main() {
        partiallyVisibleSourcesRemainEligible()
        aThinPositiveIntersectionRemainsEligible()
        touchingEdgesAreNotVisible()
        disjointSourcesAreNotVisible()
    }

    private static func partiallyVisibleSourcesRemainEligible() {
        let source = CGRect(x: -40, y: 20, width: 100, height: 80)
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 640)
        precondition(
            LevixelUniSourceGeometry.positiveIntersection(source, viewport)
                == CGRect(x: 0, y: 20, width: 60, height: 80)
        )
    }

    private static func aThinPositiveIntersectionRemainsEligible() {
        let source = CGRect(x: 319.75, y: 20, width: 100, height: 80)
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 640)
        precondition(
            LevixelUniSourceGeometry.positiveIntersection(source, viewport)?.width == 0.25,
            "Every positive-area intersection must remain eligible"
        )
    }

    private static func touchingEdgesAreNotVisible() {
        let source = CGRect(x: 320, y: 20, width: 100, height: 80)
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 640)
        precondition(LevixelUniSourceGeometry.positiveIntersection(source, viewport) == nil)
    }

    private static func disjointSourcesAreNotVisible() {
        let source = CGRect(x: 500, y: 20, width: 100, height: 80)
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 640)
        precondition(LevixelUniSourceGeometry.positiveIntersection(source, viewport) == nil)
    }
}
