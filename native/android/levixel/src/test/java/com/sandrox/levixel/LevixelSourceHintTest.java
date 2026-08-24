package com.sandrox.levixel;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public final class LevixelSourceHintTest {
    private static final float TOLERANCE = 0.001f;

    @Test
    public void coverPreservesCropAndCornerRadius() {
        LevixelSourceHint hint = hint(10f, 20f, 100f, 50f, LevixelSourceHint.ObjectFit.COVER, 8f);

        LevixelSourceHint.ResolvedGeometry geometry = hint.resolve(0f, 0f, 200f, 200f, 0f, 0f);

        assertNotNull(geometry);
        assertRect(geometry, 10f, 20f, 110f, 70f);
        assertEquals(0f, geometry.contentLeft, TOLERANCE);
        assertEquals(-25f, geometry.contentTop, TOLERANCE);
        assertEquals(100f, geometry.contentRight, TOLERANCE);
        assertEquals(75f, geometry.contentBottom, TOLERANCE);
        assertEquals(8f, geometry.cornerRadius, TOLERANCE);
    }

    @Test
    public void containStartsFromVisibleImageInsteadOfEmptyContainerArea() {
        LevixelSourceHint hint = hint(10f, 20f, 100f, 50f, LevixelSourceHint.ObjectFit.CONTAIN, 8f);

        LevixelSourceHint.ResolvedGeometry geometry = hint.resolve(0f, 0f, 200f, 200f, 0f, 0f);

        assertNotNull(geometry);
        assertRect(geometry, 35f, 20f, 85f, 70f);
        assertEquals(0f, geometry.contentLeft, TOLERANCE);
        assertEquals(0f, geometry.contentTop, TOLERANCE);
        assertEquals(50f, geometry.contentRight, TOLERANCE);
        assertEquals(50f, geometry.contentBottom, TOLERANCE);
        assertEquals(0f, geometry.cornerRadius, TOLERANCE);
    }

    @Test
    public void sourceOutsideOverlayFallsBackInsteadOfFlyingOffscreen() {
        LevixelSourceHint hint = hint(240f, 20f, 100f, 50f, LevixelSourceHint.ObjectFit.COVER, 8f);

        assertNull(hint.resolve(0f, 0f, 200f, 200f, 0f, 0f));
    }

    @Test
    public void partiallyVisibleSourceIsClippedAndDoesNotInventRoundedCorners() {
        LevixelSourceHint hint = hint(-20f, 20f, 100f, 50f, LevixelSourceHint.ObjectFit.FILL, 8f);

        LevixelSourceHint.ResolvedGeometry geometry = hint.resolve(0f, 0f, 200f, 200f, 0f, 0f);

        assertNotNull(geometry);
        assertRect(geometry, 0f, 20f, 80f, 70f);
        assertEquals(-20f, geometry.contentLeft, TOLERANCE);
        assertEquals(0f, geometry.cornerRadius, TOLERANCE);
    }

    private static LevixelSourceHint hint(
            float left,
            float top,
            float width,
            float height,
            LevixelSourceHint.ObjectFit objectFit,
            float cornerRadius
    ) {
        return new LevixelSourceHint(
                left,
                top,
                width,
                height,
                100f,
                100f,
                objectFit,
                cornerRadius
        );
    }

    private static void assertRect(
            LevixelSourceHint.ResolvedGeometry geometry,
            float left,
            float top,
            float right,
            float bottom
    ) {
        assertEquals(left, geometry.visibleLeft, TOLERANCE);
        assertEquals(top, geometry.visibleTop, TOLERANCE);
        assertEquals(right, geometry.visibleRight, TOLERANCE);
        assertEquals(bottom, geometry.visibleBottom, TOLERANCE);
    }
}
