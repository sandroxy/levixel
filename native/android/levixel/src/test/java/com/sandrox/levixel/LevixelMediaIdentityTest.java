package com.sandrox.levixel;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public final class LevixelMediaIdentityTest {
    @Test
    public void viewerSessionCopiesItemsWithUniqueStableIds() {
        List<LevixelMediaItem> items = new ArrayList<>(Arrays.asList(
                item("first"),
                item("second")
        ));

        List<LevixelMediaItem> snapshot = LevixelViewerOverlayView.copyValidatedItems(items);

        assertEquals(items, snapshot);
        assertNotSame(items, snapshot);
        items.clear();
        assertEquals(2, snapshot.size());
    }

    @Test
    public void viewerSessionRejectsMissingAndDuplicateStableIds() {
        assertInvalid(new ArrayList<>(), "at least one media item");
        assertInvalid(Arrays.asList(item("first"), item("first")), "must be unique");
        assertInvalid(Arrays.asList(item("first"), item("")), "must be non-empty");
        assertInvalid(Arrays.asList(item("first"), null), "must be non-empty");
    }

    private static void assertInvalid(List<LevixelMediaItem> items, String message) {
        try {
            LevixelViewerOverlayView.copyValidatedItems(items);
            fail("Expected invalid stable media identity to be rejected.");
        } catch (IllegalArgumentException error) {
            if (!error.getMessage().contains(message)) {
                throw error;
            }
        }
    }

    private static LevixelMediaItem item(String id) {
        return new LevixelMediaItem(
                id,
                LevixelMediaItem.MediaType.IMAGE,
                "https://example.com/full.jpg",
                "https://example.com/thumbnail.jpg"
        );
    }
}
