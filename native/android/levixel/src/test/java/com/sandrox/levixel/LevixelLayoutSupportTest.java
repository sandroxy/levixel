package com.sandrox.levixel;

import static org.junit.Assert.assertEquals;

import android.graphics.RectF;

import org.junit.Test;

public final class LevixelLayoutSupportTest {
    private static final float TOLERANCE = 0.001f;

    @Test
    public void fullSourcePreservesAndClampsTheDeclaredCornerRadius() {
        RectF source = rect(10f, 20f, 110f, 80f);

        assertEquals(
                8f,
                LevixelLayoutSupport.resolveVisibleCornerRadius(
                        source,
                        rect(10f, 20f, 110f, 80f),
                        8f
                ),
                TOLERANCE
        );
        assertEquals(
                30f,
                LevixelLayoutSupport.resolveVisibleCornerRadius(
                        source,
                        rect(10f, 20f, 110f, 80f),
                        80f
                ),
                TOLERANCE
        );
    }

    @Test
    public void clippedSourceDoesNotInventRoundedViewportCorners() {
        RectF source = rect(10f, 20f, 110f, 80f);
        RectF clipped = rect(10f, 20f, 100f, 80f);

        assertEquals(
                0f,
                LevixelLayoutSupport.resolveVisibleCornerRadius(source, clipped, 8f),
                TOLERANCE
        );
    }

    @Test
    public void absentOrInvalidRadiusResolvesToSquareGeometry() {
        RectF source = rect(10f, 20f, 110f, 80f);

        assertEquals(
                0f,
                LevixelLayoutSupport.resolveVisibleCornerRadius(
                        source,
                        rect(10f, 20f, 110f, 80f),
                        0f
                ),
                TOLERANCE
        );
        assertEquals(
                0f,
                LevixelLayoutSupport.resolveVisibleCornerRadius(
                        source,
                        rect(10f, 20f, 110f, 80f),
                        Float.NaN
                ),
                TOLERANCE
        );
    }

    private static RectF rect(float left, float top, float right, float bottom) {
        RectF rect = new RectF();
        rect.left = left;
        rect.top = top;
        rect.right = right;
        rect.bottom = bottom;
        return rect;
    }
}
