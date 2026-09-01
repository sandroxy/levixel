package com.sandrox.levixel;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;

import org.junit.Test;

public class LevixelSharedElementNamesTest {
    @Test
    public void galleryAndItemBoundariesCannotCollide() {
        assertNotEquals(
                LevixelSharedElementNames.forItem("a:b", item("c")),
                LevixelSharedElementNames.forItem("a", item("b:c"))
        );
    }

    @Test
    public void itemAndIndexUseIndependentNamespaces() {
        assertNotEquals(
                LevixelSharedElementNames.forItem("gallery", item("0")),
                LevixelSharedElementNames.forIndex("gallery", 0)
        );
    }

    @Test
    public void encodedNamesRemainDeterministicForUnicodeAndDelimiters() {
        String first = LevixelSharedElementNames.forItem("相册:a", item("媒体:一"));
        String second = LevixelSharedElementNames.forItem("相册:a", item("媒体:一"));
        String different = LevixelSharedElementNames.forItem("相册", item("a:媒体:一"));

        assertEquals(first, second);
        assertNotEquals(first, different);
    }

    @Test
    public void nullAndEmptyGalleryKeepTheSamePublicScope() {
        assertEquals(
                LevixelSharedElementNames.forItem(null, item("cover")),
                LevixelSharedElementNames.forItem("", item("cover"))
        );
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
