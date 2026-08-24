package com.sandrox.levixel;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

public final class LevixelSharedElementNames {
    private static final String PREFIX = "levixel:media:";

    private LevixelSharedElementNames() {
    }

    @NonNull
    public static String forItem(@NonNull LevixelMediaItem item) {
        return forItem(null, item);
    }

    @NonNull
    public static String forItem(@Nullable String galleryId, @NonNull LevixelMediaItem item) {
        return forId(galleryId, item.getId());
    }

    @NonNull
    public static String forIndex(int index) {
        return forIndex(null, index);
    }

    @NonNull
    public static String forIndex(@Nullable String galleryId, int index) {
        return forId(galleryId, String.valueOf(index));
    }

    @NonNull
    private static String forId(@Nullable String galleryId, @NonNull String id) {
        if (galleryId == null || galleryId.isEmpty()) {
            return PREFIX + id;
        }
        return PREFIX + galleryId + ":" + id;
    }
}
