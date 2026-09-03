package com.sandrox.levixel.uniapp.runtime;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

import android.graphics.RectF;

import com.sandrox.levixel.LevixelSourceHint;

import org.junit.Test;

public final class LevixelUniSourceHintsTest {
    private static final float TOLERANCE = 0.001f;

    @Test
    public void mapsViewportCssPixelsIntoWindowPixels() {
        LevixelSourceHint mapped = LevixelUniSourceHints.map(
                hint("viewport", 3d),
                4f,
                30f,
                rect(4f, 30f, 404f, 830f),
                true,
                2f
        );

        assertNotNull(mapped);
        assertEquals(40f, mapped.getSourceLeftInWindow(), TOLERANCE);
        assertEquals(102f, mapped.getSourceTopInWindow(), TOLERANCE);
        assertEquals(300f, mapped.getSourceWidth(), TOLERANCE);
        assertEquals(240f, mapped.getSourceHeight(), TOLERANCE);
    }

    @Test
    public void fallsBackToDisplayDensityForOlderCallers() {
        LevixelSourceHint mapped = LevixelUniSourceHints.map(
                hint("screen", null),
                0f,
                0f,
                new RectF(),
                false,
                2f
        );

        assertNotNull(mapped);
        assertEquals(24f, mapped.getSourceLeftInWindow(), TOLERANCE);
        assertEquals(48f, mapped.getSourceTopInWindow(), TOLERANCE);
    }

    @Test
    public void rejectsViewportHintWhenViewportCannotBeResolved() {
        assertNull(LevixelUniSourceHints.map(
                hint("viewport", 3d),
                0f,
                0f,
                new RectF(),
                false,
                2f
        ));
    }

    @Test
    public void viewportHintUsesTheVisibleViewportAsItsClip() {
        LevixelSourceHint mapped = LevixelUniSourceHints.map(
                hint("viewport", 1d),
                0f,
                0f,
                rect(0f, 30f, 100f, 100f),
                true,
                1f
        );

        assertNotNull(mapped);
    }

    @Test
    public void viewportHintOutsideTheVisibleViewportIsDiscarded() {
        assertNull(LevixelUniSourceHints.map(
                hint("viewport", 1d),
                0f,
                0f,
                rect(200f, 200f, 300f, 300f),
                true,
                1f
        ));
    }

    private static RectF rect(float left, float top, float right, float bottom) {
        RectF rect = new RectF();
        rect.left = left;
        rect.top = top;
        rect.right = right;
        rect.bottom = bottom;
        return rect;
    }

    private static LevixelUniContract.SourceHint hint(String coordinateSpace, Double rectScale) {
        return new LevixelUniContract.SourceHint(
                new LevixelUniContract.SourceRect(12d, 24d, 100d, 80d),
                new LevixelUniContract.ImageSize(400d, 600d),
                "cover",
                coordinateSpace,
                rectScale,
                6d
        );
    }
}
