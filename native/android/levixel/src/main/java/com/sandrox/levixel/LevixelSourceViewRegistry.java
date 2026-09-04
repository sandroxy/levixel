package com.sandrox.levixel;

import android.graphics.Rect;
import android.view.View;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.view.ViewCompat;

import java.lang.ref.WeakReference;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public final class LevixelSourceViewRegistry {
    private static final Map<String, SourceViewEntry> SOURCE_VIEWS = new HashMap<>();

    private static final class SourceViewEntry {
        private final WeakReference<ImageView> imageView;
        private final float cornerRadius;

        private SourceViewEntry(@NonNull ImageView imageView, float cornerRadius) {
            this.imageView = new WeakReference<>(imageView);
            this.cornerRadius = cornerRadius;
        }
    }

    private LevixelSourceViewRegistry() {
    }

    public static synchronized void register(@NonNull String key, @NonNull ImageView imageView) {
        register(key, imageView, 0f);
    }

    public static synchronized void register(
            @NonNull String key,
            @NonNull ImageView imageView,
            float cornerRadius
    ) {
        if (!Float.isFinite(cornerRadius) || cornerRadius < 0f) {
            throw new IllegalArgumentException(
                    "Levixel source corner radius must be a non-negative finite number."
            );
        }
        cleanupLocked();
        if (!hasUsableGeometry(imageView)) {
            SourceViewEntry existingEntry = SOURCE_VIEWS.get(key);
            ImageView existingImageView = resolveImageView(existingEntry);
            boolean keepExisting = existingImageView != null
                    && existingImageView != imageView
                    && hasUsableGeometry(existingImageView);
            clearMappingsForViewLocked(imageView);
            if (keepExisting) {
                SOURCE_VIEWS.put(key, existingEntry);
                return;
            }
            SOURCE_VIEWS.remove(key);
            return;
        }

        SourceViewEntry previousEntry = SOURCE_VIEWS.get(key);
        ImageView previousImageView = resolveImageView(previousEntry);
        if (!isPreferredSourceView(imageView)
                && previousImageView != null
                && previousImageView != imageView
                && isPreferredSourceView(previousImageView)) {
            clearMappingsForViewLocked(imageView);
            SOURCE_VIEWS.put(key, previousEntry);
            return;
        }

        clearMappingsForViewLocked(imageView);
        SOURCE_VIEWS.put(key, new SourceViewEntry(imageView, cornerRadius));
        ViewCompat.setTransitionName(imageView, key);
    }

    public static synchronized void unregisterView(@NonNull ImageView imageView) {
        clearMappingsForViewLocked(imageView);
    }

    @Nullable
    public static synchronized ImageView find(@NonNull String key) {
        cleanupLocked();
        SourceViewEntry entry = SOURCE_VIEWS.get(key);
        if (entry == null) {
            return null;
        }
        ImageView imageView = entry.imageView.get();
        if (imageView == null || !imageView.isAttachedToWindow()) {
            SOURCE_VIEWS.remove(key);
            return null;
        }
        if (!hasUsableGeometry(imageView)) {
            SOURCE_VIEWS.remove(key);
            return null;
        }
        return imageView;
    }

    @Nullable
    public static synchronized ImageView findVisible(@NonNull String key) {
        ImageView imageView = find(key);
        if (imageView == null) {
            return null;
        }
        Rect visibleRect = new Rect();
        return imageView.getGlobalVisibleRect(visibleRect) && !visibleRect.isEmpty()
                ? imageView
                : null;
    }

    static synchronized float cornerRadiusForView(@Nullable ImageView imageView) {
        if (imageView == null) {
            return 0f;
        }
        cleanupLocked();
        for (SourceViewEntry entry : SOURCE_VIEWS.values()) {
            if (entry.imageView.get() == imageView) {
                return entry.cornerRadius;
            }
        }
        return 0f;
    }

    @Nullable
    private static ImageView resolveImageView(@Nullable SourceViewEntry entry) {
        return entry != null ? entry.imageView.get() : null;
    }

    private static boolean hasUsableGeometry(@Nullable ImageView imageView) {
        return imageView != null
                && imageView.isAttachedToWindow()
                && imageView.getWidth() > 0
                && imageView.getHeight() > 0;
    }

    private static boolean isPreferredSourceView(@Nullable ImageView imageView) {
        return hasUsableGeometry(imageView)
                && imageView.getVisibility() == View.VISIBLE
                && imageView.isShown();
    }

    private static void clearMappingsForViewLocked(@NonNull ImageView imageView) {
        Iterator<Map.Entry<String, SourceViewEntry>> iterator = SOURCE_VIEWS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<String, SourceViewEntry> entry = iterator.next();
            ImageView mappedView = entry.getValue().imageView.get();
            if (mappedView == null || mappedView == imageView) {
                iterator.remove();
            }
        }
    }

    private static void cleanupLocked() {
        Iterator<Map.Entry<String, SourceViewEntry>> iterator = SOURCE_VIEWS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<String, SourceViewEntry> entry = iterator.next();
            ImageView mappedView = entry.getValue().imageView.get();
            if (mappedView == null) {
                iterator.remove();
            }
        }
    }
}
