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
                LevixelLayoutSupport.resolveSourceCornerRadius(
                        source,
                        8f
                ),
                TOLERANCE
        );
        assertEquals(
                30f,
                LevixelLayoutSupport.resolveSourceCornerRadius(
                        source,
                        80f
                ),
                TOLERANCE
        );
    }

    @Test
    public void absentOrInvalidRadiusResolvesToSquareGeometry() {
        RectF source = rect(10f, 20f, 110f, 80f);

        assertEquals(
                0f,
                LevixelLayoutSupport.resolveSourceCornerRadius(
                        source,
                        0f
                ),
                TOLERANCE
        );
        assertEquals(
                0f,
                LevixelLayoutSupport.resolveSourceCornerRadius(
                        source,
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
