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
    private static final Map<String, WeakReference<ImageView>> SOURCE_VIEWS = new HashMap<>();

    private LevixelSourceViewRegistry() {
    }

    public static synchronized void register(@NonNull String key, @NonNull ImageView imageView) {
        cleanupLocked();
        if (!hasUsableGeometry(imageView)) {
            ImageView existingImageView = resolveMappedViewLocked(key);
            boolean keepExisting = existingImageView != null
                    && existingImageView != imageView
                    && hasUsableGeometry(existingImageView);
            clearMappingsForViewLocked(imageView);
            if (keepExisting) {
                SOURCE_VIEWS.put(key, new WeakReference<>(existingImageView));
                return;
            }
            SOURCE_VIEWS.remove(key);
            return;
        }

        ImageView previousImageView = resolveMappedViewLocked(key);
        if (!isPreferredSourceView(imageView)
                && previousImageView != null
                && previousImageView != imageView
                && isPreferredSourceView(previousImageView)) {
            clearMappingsForViewLocked(imageView);
            SOURCE_VIEWS.put(key, new WeakReference<>(previousImageView));
            return;
        }

        clearMappingsForViewLocked(imageView);
        SOURCE_VIEWS.put(key, new WeakReference<>(imageView));
        ViewCompat.setTransitionName(imageView, key);
    }

    public static synchronized void unregisterView(@NonNull ImageView imageView) {
        clearMappingsForViewLocked(imageView);
    }

    @Nullable
    public static synchronized ImageView find(@NonNull String key) {
        cleanupLocked();
        WeakReference<ImageView> reference = SOURCE_VIEWS.get(key);
        if (reference == null) {
            return null;
        }
        ImageView imageView = reference.get();
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

    @Nullable
    private static ImageView resolveMappedViewLocked(@NonNull String key) {
        WeakReference<ImageView> reference = SOURCE_VIEWS.get(key);
        return reference != null ? reference.get() : null;
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
        Iterator<Map.Entry<String, WeakReference<ImageView>>> iterator = SOURCE_VIEWS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<String, WeakReference<ImageView>> entry = iterator.next();
            ImageView mappedView = entry.getValue().get();
            if (mappedView == null || mappedView == imageView) {
                iterator.remove();
            }
        }
    }

    private static void cleanupLocked() {
        Iterator<Map.Entry<String, WeakReference<ImageView>>> iterator = SOURCE_VIEWS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<String, WeakReference<ImageView>> entry = iterator.next();
            ImageView mappedView = entry.getValue().get();
            if (mappedView == null) {
                iterator.remove();
            }
        }
    }
}
