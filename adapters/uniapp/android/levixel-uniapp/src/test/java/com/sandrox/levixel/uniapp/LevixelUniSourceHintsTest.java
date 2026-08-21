package com.sandrox.levixel.uniapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

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
                false,
                2f
        ));
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
