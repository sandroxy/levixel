package com.sandrox.levixel;

import android.app.Activity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import androidx.core.view.ViewCompat;
import java.util.ArrayList;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class LevixelSourceViewRegistryTest {
    private ActivityController<Activity> activity;
    private FrameLayout root;
    private final List<LevixelSourceViewRegistry.HiddenSource> leases = new ArrayList<>();

    @Before public void setUp() {
        activity = Robolectric.buildActivity(Activity.class).setup().visible();
        root = new FrameLayout(activity.get());
        activity.get().setContentView(root);
        root.layout(0, 0, 500, 500);
    }

    @After public void tearDown() {
        for (LevixelSourceViewRegistry.HiddenSource lease : leases) lease.close();
        activity.pause().stop().destroy();
        LevixelSourceViewRegistry.find("media"); // Purge detached weak registrations.
    }

    @Test public void swappingImagesKeepsTheContainerHiddenAndReplacesTheAnchor() {
        FrameLayout source = source(0.6f);
        ImageView first = image(source);
        ImageView second = image(source);
        LevixelSourceViewRegistry.registerSource("media", first, 12f, source);
        LevixelSourceViewRegistry.HiddenSource lease = hide("media");
        first.setVisibility(View.GONE);
        LevixelSourceViewRegistry.registerSource("media", second, 12f, source);

        assertSame(second, LevixelSourceViewRegistry.find("media"));
        assertSame(second, LevixelSourceViewRegistry.findVisible("media"));
        assertEquals(12f, LevixelSourceViewRegistry.cornerRadiusForView(second), 0f);
        assertNull(ViewCompat.getTransitionName(first));
        assertEquals("media", ViewCompat.getTransitionName(second));
        assertEquals(0f, source.getAlpha(), 0f);
        assertEquals(1f, second.getAlpha(), 0f);
        lease.close();
        assertEquals(0.6f, source.getAlpha(), 0f);
    }

    @Test public void pendingDrawableDoesNotReleaseThumbnailVisibility() {
        FrameLayout source = source(0.7f);
        ImageView image = image(source);
        LevixelSourceViewRegistry.registerSource("media", image, 0f, source);
        LevixelSourceViewRegistry.HiddenSource lease = hide("media");
        LevixelSourceViewRegistry.registerSource("media", null, 0f, source);
        assertNull(LevixelSourceViewRegistry.find("media"));
        assertNull(ViewCompat.getTransitionName(image));
        assertEquals(0f, source.getAlpha(), 0f);

        LevixelSourceViewRegistry.registerSource("media", image, 0f, source);
        assertSame(image, LevixelSourceViewRegistry.find("media"));
        assertEquals(0f, source.getAlpha(), 0f);
        lease.close();
        assertEquals(0.7f, source.getAlpha(), 0f);
    }

    @Test public void aSourceMountedAfterPagingIsHiddenUntilDismissal() {
        LevixelSourceViewRegistry.HiddenSource lease = hide("media");
        FrameLayout source = source(1f);
        LevixelSourceViewRegistry.registerSource("media", null, 0f, source);
        assertEquals(0f, source.getAlpha(), 0f);
        ImageView image = image(source);
        LevixelSourceViewRegistry.registerSource("media", image, 0f, source);
        assertSame(image, LevixelSourceViewRegistry.find("media"));
        lease.close();
        assertEquals(1f, source.getAlpha(), 0f);
    }

    @Test public void recycledSourceRestoresOldIdentityAndFollowsItsReplacement() {
        FrameLayout recycled = source(0.6f);
        ImageView image = image(recycled);
        LevixelSourceViewRegistry.registerSource("media", image, 0f, recycled);
        LevixelSourceViewRegistry.HiddenSource lease = hide("media");
        LevixelSourceViewRegistry.registerSource("other", image, 0f, recycled);
        assertNull(LevixelSourceViewRegistry.find("media"));
        assertSame(image, LevixelSourceViewRegistry.find("other"));
        assertEquals(0.6f, recycled.getAlpha(), 0f);

        FrameLayout replacement = source(0.8f);
        LevixelSourceViewRegistry.registerSource("media", image(replacement), 0f, replacement);
        assertEquals(0f, replacement.getAlpha(), 0f);
        lease.close();
        lease.close();
        assertEquals(0.8f, replacement.getAlpha(), 0f);
        assertEquals(0.6f, recycled.getAlpha(), 0f);
    }

    @Test public void recyclingBetweenTwoHiddenIdentitiesDoesNotSaveZeroAlpha() {
        FrameLayout source = source(0.5f);
        ImageView image = image(source);
        LevixelSourceViewRegistry.registerSource("media", image, 0f, source);
        LevixelSourceViewRegistry.HiddenSource first = hide("media");
        LevixelSourceViewRegistry.HiddenSource second = hide("other");
        LevixelSourceViewRegistry.registerSource("other", image, 0f, source);
        assertEquals(0f, source.getAlpha(), 0f);
        first.close();
        assertEquals(0f, source.getAlpha(), 0f);
        second.close();
        assertEquals(0.5f, source.getAlpha(), 0f);
    }

    @Test public void overlappingViewersRestoreOnlyAfterTheLastOwnerCloses() {
        FrameLayout source = source(0.9f);
        LevixelSourceViewRegistry.registerSource("media", image(source), 0f, source);
        LevixelSourceViewRegistry.HiddenSource first = hide("media");
        LevixelSourceViewRegistry.HiddenSource second = hide("media");
        first.close();
        assertEquals(0f, source.getAlpha(), 0f);
        second.close();
        assertEquals(0.9f, source.getAlpha(), 0f);
    }

    @Test public void unregisteringOldContainerCannotRemoveTheReplacement() {
        FrameLayout first = source(1f);
        LevixelSourceViewRegistry.registerSource("media", image(first), 0f, first);
        hide("media");
        FrameLayout second = source(0.8f);
        ImageView image = image(second);
        LevixelSourceViewRegistry.registerSource("media", image, 0f, second);
        LevixelSourceViewRegistry.unregisterSource(first);
        assertSame(image, LevixelSourceViewRegistry.find("media"));
        assertEquals(1f, first.getAlpha(), 0f);
        assertEquals(0f, second.getAlpha(), 0f);
        LevixelSourceViewRegistry.unregisterSource(second);
        assertNull(LevixelSourceViewRegistry.find("media"));
        assertEquals(0.8f, second.getAlpha(), 0f);
    }

    @Test public void nativeImageOnlyRegistrationAndDetachStillRestoreVisibility() {
        FrameLayout source = source(1f);
        ImageView image = image(source);
        image.setAlpha(0.6f);
        LevixelSourceViewRegistry.register("media", image, 3f);
        hide("media");
        assertEquals(0f, image.getAlpha(), 0f);
        assertEquals(1f, source.getAlpha(), 0f);
        root.removeView(source);
        assertNull(LevixelSourceViewRegistry.find("media"));
        assertNull(ViewCompat.getTransitionName(image));
        assertEquals(0.6f, image.getAlpha(), 0f);
    }

    @Test public void aDifferentViewsTransitionNameIsNotCleared() {
        FrameLayout source = source(1f);
        ImageView image = image(source);
        LevixelSourceViewRegistry.register("media", image);
        ViewCompat.setTransitionName(image, "host-owned");
        LevixelSourceViewRegistry.unregisterView(image);
        assertEquals("host-owned", ViewCompat.getTransitionName(image));
    }

    @Test public void visibilityOwnerMustContainItsImage() {
        FrameLayout source = source(1f);
        ImageView image = image(source);
        FrameLayout unrelated = source(1f);
        assertThrows(IllegalArgumentException.class,
                () -> LevixelSourceViewRegistry.registerSource("media", image, 0f, unrelated));
    }

    private LevixelSourceViewRegistry.HiddenSource hide(String key) {
        LevixelSourceViewRegistry.HiddenSource lease = LevixelSourceViewRegistry.hide(key);
        leases.add(lease);
        return lease;
    }

    private FrameLayout source(float alpha) {
        FrameLayout source = new FrameLayout(activity.get());
        root.addView(source, new FrameLayout.LayoutParams(100, 100));
        source.layout(0, 0, 100, 100);
        source.setAlpha(alpha);
        return source;
    }

    private ImageView image(FrameLayout source) {
        ImageView image = new ImageView(activity.get());
        source.addView(image, new FrameLayout.LayoutParams(100, 100));
        image.layout(0, 0, 100, 100);
        return image;
    }
}
