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
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

public final class LevixelSourceViewRegistry {
    private static final Map<String, LinkedHashMap<String, SourceViewEntry>> SOURCE_VIEWS = new HashMap<>();
    private static final Map<View, String> SOURCE_IDS = new WeakHashMap<>();
    private static final Set<HiddenSource> HIDDEN_SOURCES = new HashSet<>();
    private static final Map<View, HiddenView> HIDDEN_VIEWS = new IdentityHashMap<>();
    private static long nextSourceId;

    private static final class SourceViewEntry {
        final String sourceId;
        final String transitionName;
        final WeakReference<View> visibilityView;
        WeakReference<ImageView> imageView;
        float cornerRadius;

        SourceViewEntry(String key, String sourceId, View owner) {
            this.sourceId = sourceId;
            this.transitionName = key + ":source:" + sourceId.length() + ":" + sourceId;
            this.visibilityView = new WeakReference<>(owner);
            this.imageView = new WeakReference<>(null);
        }
    }

    private static final class HiddenView {
        final float previousAlpha;
        int owners;
        HiddenView(View view) { previousAlpha = view.getAlpha(); }
    }

    /** A session remembers a source instance, while its image and geometry may change. */
    static final class Selection {
        final String key;
        final WeakReference<View> scope;
        private SourceViewEntry selected;
        private final String initialSourceId;
        private boolean allowsFallback;

        Selection(String key, @Nullable String sourceId, @Nullable View scope) {
            this.key = key;
            this.initialSourceId = sourceId;
            this.allowsFallback = sourceId == null;
            this.scope = new WeakReference<>(scope);
        }

        @Nullable ImageView image() {
            synchronized (LevixelSourceViewRegistry.class) {
                cleanupLocked();
                SourceViewEntry entry = resolve();
                updateHiddenSources();
                ImageView image = entry == null ? null : entry.imageView.get();
                return hasUsableGeometry(image) && entry != null && isVisibleImage(image, entry) ? image : null;
            }
        }

        void allowFallback() {
            synchronized (LevixelSourceViewRegistry.class) {
                allowsFallback = true;
                updateHiddenSources();
            }
        }

        @Nullable private SourceViewEntry resolve() {
            Map<String, SourceViewEntry> entries = SOURCE_VIEWS.get(key);
            if (entries == null) { selected = null; return null; }
            if (selected != null && entries.get(selected.sourceId) == selected && isEligible(selected, scope.get())) {
                return selected;
            }
            selected = null;
            if (!allowsFallback) {
                SourceViewEntry exact = entries.get(initialSourceId);
                if (exact != null && isEligible(exact, scope.get())) selected = exact;
            } else {
                for (SourceViewEntry entry : entries.values()) {
                    if (isEligible(entry, scope.get())) { selected = entry; break; }
                }
            }
            return selected;
        }
    }

    static final class HiddenSource implements AutoCloseable {
        final Selection selection;
        private View view;
        HiddenSource(Selection selection) { this.selection = selection; }
        @Override public void close() {
            synchronized (LevixelSourceViewRegistry.class) {
                if (HIDDEN_SOURCES.remove(this)) releaseHiddenView(this);
            }
        }
    }

    private LevixelSourceViewRegistry() {}

    public static synchronized void register(@NonNull String key, @NonNull ImageView imageView) {
        register(key, imageView, 0f);
    }

    public static synchronized void register(@NonNull String key, @NonNull ImageView imageView, float cornerRadius) {
        registerSource(key, imageView, cornerRadius, imageView);
    }

    public static synchronized void registerSource(
            @NonNull String key, @Nullable ImageView imageView, float cornerRadius, @NonNull View visibilityView
    ) {
        registerSource(key, imageView, cornerRadius, visibilityView, null);
    }

    /** Null images keep a stable source registered while its loader replaces the displayed image. */
    public static synchronized void registerSource(
            @NonNull String key, @Nullable ImageView imageView, float cornerRadius,
            @NonNull View visibilityView, @Nullable String sourceId
    ) {
        if (!Float.isFinite(cornerRadius) || cornerRadius < 0f) {
            throw new IllegalArgumentException("Levixel source corner radius must be a non-negative finite number.");
        }
        if (sourceId != null && sourceId.isEmpty()) throw new IllegalArgumentException("Levixel source ID must not be empty.");
        if (imageView != null && !belongsTo(imageView, visibilityView)) {
            throw new IllegalArgumentException("Levixel visibility view must contain its source image.");
        }
        cleanupLocked();
        String identity = sourceId;
        if (identity == null) {
            identity = SOURCE_IDS.get(visibilityView);
            if (identity == null) {
                identity = "native-" + (++nextSourceId);
                SOURCE_IDS.put(visibilityView, identity);
            }
        }
        LinkedHashMap<String, SourceViewEntry> entries = SOURCE_VIEWS.get(key);
        SourceViewEntry entry = entries == null ? null : entries.get(identity);
        if (entry != null && entry.visibilityView.get() != visibilityView) {
            throw new IllegalArgumentException("Levixel source ID is already registered by another view.");
        }
        // Keep the same entry (and insertion order) for image/geometry updates.
        // Rebinding a container to another media identity removes only that container.
        removeMappings(visibilityView, imageView, entry);
        if (entry == null) entry = new SourceViewEntry(key, identity, visibilityView);
        clearTransitionName(entry);
        entry.imageView = new WeakReference<>(imageView);
        entry.cornerRadius = cornerRadius;
        // removeMappings may have removed the last entry for this key.
        entries = SOURCE_VIEWS.get(key);
        if (entries == null) {
            entries = new LinkedHashMap<>();
            SOURCE_VIEWS.put(key, entries);
        }
        entries.put(identity, entry);
        if (imageView != null) ViewCompat.setTransitionName(imageView, entry.transitionName);
        updateHiddenSources();
    }

    public static synchronized void unregisterSource(@NonNull View visibilityView) {
        removeMappings(visibilityView, null, null);
        updateHiddenSources();
    }

    public static synchronized void unregisterView(@NonNull ImageView imageView) {
        removeMappings(null, imageView, null);
        updateHiddenSources();
    }

    /** Legacy lookup uses stable registration order. Viewers retain their own Selection. */
    @Nullable public static synchronized ImageView find(@NonNull String key) {
        cleanupLocked();
        Map<String, SourceViewEntry> entries = SOURCE_VIEWS.get(key);
        if (entries != null) {
            for (SourceViewEntry entry : entries.values()) {
                ImageView image = entry.imageView.get();
                if (hasUsableGeometry(image) && image.isShown()) return image;
            }
        }
        return null;
    }

    @Nullable public static synchronized ImageView findVisible(@NonNull String key) {
        return new Selection(key, null, null).image();
    }

    static synchronized float cornerRadiusForView(@Nullable ImageView imageView) {
        if (imageView == null) return 0f;
        for (Map<String, SourceViewEntry> entries : SOURCE_VIEWS.values()) {
            for (SourceViewEntry entry : entries.values()) {
                if (entry.imageView.get() == imageView) return entry.cornerRadius;
            }
        }
        return 0f;
    }

    static synchronized HiddenSource hide(@NonNull String key) {
        return hide(new Selection(key, null, null));
    }

    static synchronized HiddenSource hide(@NonNull Selection selection) {
        HiddenSource source = new HiddenSource(selection);
        HIDDEN_SOURCES.add(source);
        updateHiddenSources();
        return source;
    }

    private static void updateHiddenSources() {
        Map<HiddenSource, View> targets = new IdentityHashMap<>();
        for (HiddenSource source : HIDDEN_SOURCES) {
            SourceViewEntry entry = source.selection.resolve();
            targets.put(source, entry == null ? null : entry.visibilityView.get());
        }
        // Release all old identities first: a recycled container must not save another lease's zero alpha.
        for (HiddenSource source : HIDDEN_SOURCES) {
            if (source.view != targets.get(source)) releaseHiddenView(source);
        }
        for (HiddenSource source : HIDDEN_SOURCES) {
            View view = targets.get(source);
            if (view == null || source.view == view) continue;
            HiddenView hidden = HIDDEN_VIEWS.get(view);
            if (hidden == null) { hidden = new HiddenView(view); HIDDEN_VIEWS.put(view, hidden); }
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

    private static boolean hasUsableGeometry(@Nullable ImageView image) {
        return image != null && image.isAttachedToWindow() && image.getWidth() > 0 && image.getHeight() > 0;
    }

    private static boolean isEligible(SourceViewEntry entry, @Nullable View scope) {
        View owner = entry.visibilityView.get();
        if (owner == null || !owner.isAttachedToWindow() || !owner.isShown()) return false;
        if (scope != null && scope.getWindowToken() != null && owner.getWindowToken() != scope.getWindowToken()) return false;
        Rect visible = new Rect();
        if (!owner.getGlobalVisibleRect(visible) || visible.isEmpty()) return false;
        View current = owner;
        while (current != null) {
            if (current.getAlpha() <= 0f && !HIDDEN_VIEWS.containsKey(current)) return false;
            current = current.getParent() instanceof View ? (View) current.getParent() : null;
        }
        return true;
    }

    private static boolean isVisibleImage(ImageView image, SourceViewEntry entry) {
        View owner = entry.visibilityView.get();
        Rect visible = new Rect();
        if (owner == null || !belongsTo(image, owner) || !image.isShown()
                || !image.getGlobalVisibleRect(visible) || visible.isEmpty()) return false;
        for (View current = image; current != owner; current = (View) current.getParent()) {
            if (current.getAlpha() <= 0f && !HIDDEN_VIEWS.containsKey(current)) return false;
        }
        return true;
    }

    private static boolean belongsTo(View image, View owner) {
        View ancestor = image;
        while (ancestor != owner && ancestor.getParent() instanceof View) ancestor = (View) ancestor.getParent();
        return ancestor == owner;
    }

    private static void removeMappings(@Nullable View owner, @Nullable ImageView image, @Nullable SourceViewEntry keeping) {
        Iterator<LinkedHashMap<String, SourceViewEntry>> galleries = SOURCE_VIEWS.values().iterator();
        while (galleries.hasNext()) {
            Map<String, SourceViewEntry> gallery = galleries.next();
            Iterator<SourceViewEntry> entries = gallery.values().iterator();
            while (entries.hasNext()) {
                SourceViewEntry entry = entries.next();
                if (entry != keeping && ((owner != null && entry.visibilityView.get() == owner)
                        || (image != null && entry.imageView.get() == image))) {
                    clearTransitionName(entry);
                    entries.remove();
                }
            }
            if (gallery.isEmpty()) galleries.remove();
        }
    }

    private static void clearTransitionName(SourceViewEntry entry) {
        ImageView image = entry.imageView.get();
        if (image != null && entry.transitionName.equals(ViewCompat.getTransitionName(image))) ViewCompat.setTransitionName(image, null);
    }

    private static void cleanupLocked() {
        Iterator<LinkedHashMap<String, SourceViewEntry>> galleries = SOURCE_VIEWS.values().iterator();
        while (galleries.hasNext()) {
            Map<String, SourceViewEntry> gallery = galleries.next();
            Iterator<SourceViewEntry> entries = gallery.values().iterator();
            while (entries.hasNext()) {
                SourceViewEntry entry = entries.next();
                View owner = entry.visibilityView.get();
                if (owner == null || !owner.isAttachedToWindow()) {
                    clearTransitionName(entry);
                    entries.remove();
                }
            }
            if (gallery.isEmpty()) galleries.remove();
        }
        updateHiddenSources();
    }
}
