package com.sandrox.levixel;

import android.graphics.Rect;
import android.view.View;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.view.ViewCompat;

import java.lang.ref.WeakReference;
import java.util.HashMap;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

public final class LevixelSourceViewRegistry {
    private static final Map<String, SourceViewEntry> SOURCE_VIEWS = new HashMap<>();
    private static final Set<HiddenSource> HIDDEN_SOURCES = new HashSet<>();
    private static final Map<View, HiddenView> HIDDEN_VIEWS = new IdentityHashMap<>();

    private static final class SourceViewEntry {
        private final WeakReference<ImageView> imageView;
        private final WeakReference<View> visibilityView;
        private final float cornerRadius;

        private SourceViewEntry(@Nullable ImageView imageView, float cornerRadius, @NonNull View visibilityView) {
            this.imageView = new WeakReference<>(imageView);
            this.visibilityView = new WeakReference<>(visibilityView);
            this.cornerRadius = cornerRadius;
        }
    }

    private static final class HiddenView {
        final float previousAlpha;
        int owners;

        HiddenView(View view) {
            previousAlpha = view.getAlpha();
        }
    }

    // The viewer owns a media identity, not a particular recyclable ImageView.
    // Registration changes move this lease to the current source, including
    // sources mounted after the viewer has already opened.
    static final class HiddenSource implements AutoCloseable {
        private final String key;
        private View view;

        private HiddenSource(String key) {
            this.key = key;
        }

        @Override public void close() {
            synchronized (LevixelSourceViewRegistry.class) {
                if (HIDDEN_SOURCES.remove(this)) releaseHiddenView(this);
            }
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
        registerSource(key, imageView, cornerRadius, imageView);
    }

    /**
     * Registers the image used for geometry and a stable thumbnail container
     * whose visibility is owned by the viewer. The image must belong to it;
     * null keeps the thumbnail hidden while its loader has no drawable yet.
     */
    public static synchronized void registerSource(
            @NonNull String key,
            @Nullable ImageView imageView,
            float cornerRadius,
            @NonNull View visibilityView
    ) {
        if (!Float.isFinite(cornerRadius) || cornerRadius < 0f) {
            throw new IllegalArgumentException(
                    "Levixel source corner radius must be a non-negative finite number."
            );
        }
        if (imageView != null) {
            View ancestor = imageView;
            while (ancestor != visibilityView && ancestor.getParent() instanceof View) {
                ancestor = (View) ancestor.getParent();
            }
            if (ancestor != visibilityView) {
                throw new IllegalArgumentException("Levixel visibility view must contain its source image.");
            }
        }
        cleanupLocked();
        if (imageView != null && !hasUsableGeometry(imageView)) {
            SourceViewEntry existingEntry = SOURCE_VIEWS.get(key);
            ImageView existingImageView = resolveImageView(existingEntry);
            boolean keepExisting = existingImageView != null
                    && existingImageView != imageView
                    && hasUsableGeometry(existingImageView);
            clearMappingsForViewLocked(imageView);
            if (keepExisting) {
                SOURCE_VIEWS.put(key, existingEntry);
                updateHiddenSources();
                return;
            }
            clearTransitionName(key, SOURCE_VIEWS.get(key));
            SOURCE_VIEWS.remove(key);
            updateHiddenSources();
            return;
        }

        SourceViewEntry previousEntry = SOURCE_VIEWS.get(key);
        ImageView previousImageView = resolveImageView(previousEntry);
        if (previousEntry != null && previousEntry.visibilityView.get() != visibilityView
                && !isPreferredSourceView(imageView)
                && previousImageView != null
                && previousImageView != imageView
                && isPreferredSourceView(previousImageView)) {
            clearMappingsForSourceLocked(visibilityView);
            SOURCE_VIEWS.put(key, previousEntry);
            updateHiddenSources();
            return;
        }

        clearMappingsForSourceLocked(visibilityView);
        if (imageView != null) clearMappingsForViewLocked(imageView);
        clearTransitionName(key, SOURCE_VIEWS.get(key));
        SOURCE_VIEWS.put(key, new SourceViewEntry(imageView, cornerRadius, visibilityView));
        if (imageView != null) ViewCompat.setTransitionName(imageView, key);
        updateHiddenSources();
    }

    public static synchronized void unregisterSource(@NonNull View visibilityView) {
        clearMappingsForSourceLocked(visibilityView);
        updateHiddenSources();
    }

    public static synchronized void unregisterView(@NonNull ImageView imageView) {
        clearMappingsForViewLocked(imageView);
        updateHiddenSources();
    }

    @Nullable
    public static synchronized ImageView find(@NonNull String key) {
        cleanupLocked();
        SourceViewEntry entry = SOURCE_VIEWS.get(key);
        if (entry == null) {
            return null;
        }
        ImageView imageView = entry.imageView.get();
        return hasUsableGeometry(imageView) ? imageView : null;
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

    static synchronized HiddenSource hide(@NonNull String key) {
        HiddenSource source = new HiddenSource(key);
        HIDDEN_SOURCES.add(source);
        updateHiddenSources();
        return source;
    }

    @Nullable
    private static View visibilityView(String key) {
        SourceViewEntry entry = SOURCE_VIEWS.get(key);
        if (entry == null) return null;
        View view = entry.visibilityView.get();
        return view != null && view.isAttachedToWindow() ? view : null;
    }

    private static void updateHiddenSources() {
        // Release old identities first, so a reused container cannot inherit
        // another media item's hidden alpha when it acquires a new lease.
        for (HiddenSource source : HIDDEN_SOURCES) {
            if (source.view != visibilityView(source.key)) releaseHiddenView(source);
        }
        for (HiddenSource source : HIDDEN_SOURCES) {
            View view = visibilityView(source.key);
            if (view == null || source.view == view) continue;
            HiddenView hidden = HIDDEN_VIEWS.get(view);
            if (hidden == null) {
                hidden = new HiddenView(view);
                HIDDEN_VIEWS.put(view, hidden);
            }
            hidden.owners++;
            source.view = view;
            view.setAlpha(0f);
        }
    }

    private static void releaseHiddenView(HiddenSource source) {
        View view = source.view;
        source.view = null;
        if (view == null) return;
        HiddenView hidden = HIDDEN_VIEWS.get(view);
        if (hidden != null && --hidden.owners == 0) {
            HIDDEN_VIEWS.remove(view);
            view.setAlpha(hidden.previousAlpha);
        }
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
            if (mappedView == imageView) {
                clearTransitionName(entry.getKey(), entry.getValue());
                iterator.remove();
            }
        }
    }

    private static void clearMappingsForSourceLocked(@NonNull View visibilityView) {
        Iterator<Map.Entry<String, SourceViewEntry>> iterator = SOURCE_VIEWS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<String, SourceViewEntry> entry = iterator.next();
            if (entry.getValue().visibilityView.get() == visibilityView) {
                clearTransitionName(entry.getKey(), entry.getValue());
                iterator.remove();
            }
        }
    }

    private static void clearTransitionName(String key, @Nullable SourceViewEntry entry) {
        ImageView image = resolveImageView(entry);
        if (image != null && key.equals(ViewCompat.getTransitionName(image))) {
            ViewCompat.setTransitionName(image, null);
        }
    }

    private static void cleanupLocked() {
        Iterator<Map.Entry<String, SourceViewEntry>> iterator = SOURCE_VIEWS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<String, SourceViewEntry> entry = iterator.next();
            View visibilityView = entry.getValue().visibilityView.get();
            if (visibilityView == null || !visibilityView.isAttachedToWindow()) {
                clearTransitionName(entry.getKey(), entry.getValue());
                iterator.remove();
            }
        }
        updateHiddenSources();
    }
}
