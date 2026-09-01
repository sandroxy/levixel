package com.sandrox.levixel;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

public final class LevixelSharedElementNames {
    private static final String PREFIX = "levixel:media:";
    private static final String ITEM_NAMESPACE = "item:";
    private static final String INDEX_NAMESPACE = "index:";

    private LevixelSharedElementNames() {
    }

    @NonNull
    public static String forItem(@NonNull LevixelMediaItem item) {
        return forItem(null, item);
    }

    @NonNull
    public static String forItem(@Nullable String galleryId, @NonNull LevixelMediaItem item) {
        return scopedName(galleryId, ITEM_NAMESPACE, item.getId());
    }

    @NonNull
    public static String forIndex(int index) {
        return forIndex(null, index);
    }

    @NonNull
    public static String forIndex(@Nullable String galleryId, int index) {
        return scopedName(galleryId, INDEX_NAMESPACE, String.valueOf(index));
    }

    @NonNull
    private static String scopedName(
            @Nullable String galleryId,
            @NonNull String namespace,
            @NonNull String value
    ) {
        String gallery = galleryId == null ? "" : galleryId;
        return PREFIX + "gallery:" + encodedPart(gallery) + ":" + namespace + encodedPart(value);
    }

    @NonNull
    private static String encodedPart(@NonNull String value) {
        return value.length() + ":" + value;
    }
}
