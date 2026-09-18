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
        String transitionName = ViewCompat.getTransitionName(first);
        LevixelSourceViewRegistry.HiddenSource lease = hide("media");
        first.setVisibility(View.GONE);
        LevixelSourceViewRegistry.registerSource("media", second, 12f, source);

        assertSame(second, LevixelSourceViewRegistry.find("media"));
        assertSame(second, LevixelSourceViewRegistry.findVisible("media"));
        assertEquals(12f, LevixelSourceViewRegistry.cornerRadiusForView(second), 0f);
        assertNull(ViewCompat.getTransitionName(first));
        assertEquals(transitionName, ViewCompat.getTransitionName(second));
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

    @Test public void everySourceCanBeSelectedWithoutDuplicatingOrHidingItsSiblings() {
        for (int count : new int[] {1, 2, 3, 5, 10}) {
            String key = "multiple-" + count;
            List<FrameLayout> sources = new ArrayList<>();
            List<ImageView> images = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                FrameLayout source = source(0.6f);
                ImageView image = image(source);
                sources.add(source);
                images.add(image);
                LevixelSourceViewRegistry.registerSource(key, image, i, source, "source-" + i);
            }
            assertEquals(count, images.stream().map(ViewCompat::getTransitionName).distinct().count());
            for (int selected = 0; selected < count; selected++) {
                LevixelSourceViewRegistry.Selection selection = new LevixelSourceViewRegistry.Selection(key, "source-" + selected, root);
                assertSame(images.get(selected), selection.image());
                assertEquals(selected, LevixelSourceViewRegistry.cornerRadiusForView(selection.image()), 0f);
                LevixelSourceViewRegistry.HiddenSource lease = hide(selection);
                selection.allowFallback();
                for (int i = count - 1; i >= 0; i--) {
                    LevixelSourceViewRegistry.registerSource(key, images.get(i), i, sources.get(i), "source-" + i);
                    assertSame(images.get(selected), selection.image());
                    assertEquals(i == selected ? 0f : 0.6f, sources.get(i).getAlpha(), 0f);
                }
                lease.close();
                assertEquals(0.6f, sources.get(selected).getAlpha(), 0f);
            }
            sources.forEach(LevixelSourceViewRegistry::unregisterSource);
        }
    }

    @Test public void selectedContainerSurvivesImageGapsAndSiblingUpdates() {
        FrameLayout first = source(0.6f);
        FrameLayout second = source(0.8f);
        ImageView firstImage = image(first);
        ImageView secondImage = image(second);
        LevixelSourceViewRegistry.registerSource("media", firstImage, 3f, first, "first");
        LevixelSourceViewRegistry.registerSource("media", secondImage, 9f, second, "second");
        LevixelSourceViewRegistry.Selection selection = new LevixelSourceViewRegistry.Selection("media", "second", root);
        LevixelSourceViewRegistry.HiddenSource lease = hide(selection);
        selection.allowFallback();
        LevixelSourceViewRegistry.registerSource("media", null, 9f, second, "second");
        assertNull(selection.image());
        assertEquals(0f, second.getAlpha(), 0f);
        assertEquals(0.6f, first.getAlpha(), 0f);
        ImageView replacement = image(second);
        LevixelSourceViewRegistry.registerSource("media", replacement, 9f, second, "second");
        assertSame(replacement, selection.image());
        LevixelSourceViewRegistry.unregisterView(secondImage);
        assertSame(replacement, selection.image());
        lease.close();
        assertEquals(0.8f, second.getAlpha(), 0f);
    }

    @Test public void missingExplicitSourceDoesNotBorrowAnotherOpeningAnchor() {
        FrameLayout source = source(0.7f);
        ImageView image = image(source);
        LevixelSourceViewRegistry.registerSource("media", image, 0f, source, "available");
        LevixelSourceViewRegistry.Selection selection = new LevixelSourceViewRegistry.Selection("media", "gone", root);
        hide(selection);
        assertNull(selection.image());
        assertEquals(0.7f, source.getAlpha(), 0f);
        selection.allowFallback();
        assertSame(image, selection.image());
        assertEquals(0f, source.getAlpha(), 0f);
    }

    @Test public void fallbackIsStableAndNeverUsesAReboundIdentity() {
        FrameLayout first = source(0.6f);
        FrameLayout clicked = source(0.8f);
        ImageView firstImage = image(first);
        ImageView clickedImage = image(clicked);
        LevixelSourceViewRegistry.registerSource("media", firstImage, 0f, first, "first");
        LevixelSourceViewRegistry.registerSource("media", clickedImage, 0f, clicked, "clicked");
        LevixelSourceViewRegistry.Selection selection = new LevixelSourceViewRegistry.Selection("media", "clicked", root);
        LevixelSourceViewRegistry.HiddenSource lease = hide(selection);
        selection.allowFallback();
        LevixelSourceViewRegistry.registerSource("other", clickedImage, 0f, clicked, "clicked");
        assertSame(firstImage, selection.image());
        assertEquals(0.8f, clicked.getAlpha(), 0f);
        assertEquals(0f, first.getAlpha(), 0f);
        LevixelSourceViewRegistry.registerSource("media", clickedImage, 0f, clicked, "clicked");
        assertSame(firstImage, selection.image());
        LevixelSourceViewRegistry.unregisterSource(first);
        assertSame(clickedImage, selection.image());
        assertEquals(0.6f, first.getAlpha(), 0f);
        lease.close();
        assertEquals(0.8f, clicked.getAlpha(), 0f);
    }

    @Test public void programmaticSelectionSkipsClippedAndHostHiddenSources() {
        FrameLayout first = source(0.6f);
        FrameLayout second = source(0.8f);
        ImageView firstImage = image(first);
        ImageView secondImage = image(second);
        LevixelSourceViewRegistry.registerSource("media", firstImage, 0f, first, "first");
        LevixelSourceViewRegistry.registerSource("media", secondImage, 0f, second, "second");
        first.offsetLeftAndRight(600);
        LevixelSourceViewRegistry.Selection selection = new LevixelSourceViewRegistry.Selection("media", null, root);
        assertSame(secondImage, selection.image());
        second.setAlpha(0f);
        assertNull(selection.image());
        first.offsetLeftAndRight(-600);
        assertSame(firstImage, selection.image());
    }

    @Test public void selectionAndRestorationHoldForEverySourceMutationCombination() {
        // Each clicked/changed pair matters: a sibling update must not steal the
        // selection, while losing the selected source must pick the oldest survivor.
        for (int count : new int[] {1, 2, 3, 5, 10}) {
            for (int clicked = 0; clicked < count; clicked++) {
                for (int changed = 0; changed < count; changed++) {
                    for (String operation : new String[] {"refresh", "image-gap", "remove", "rebind", "clip", "host-hide"}) {
                        verifyMutationCombination(count, clicked, changed, operation);
                    }
                }
            }
        }
    }

    private void verifyMutationCombination(int count, int clicked, int changed, String operation) {
        String context = "count=" + count + ", clicked=" + clicked + ", changed=" + changed + ", " + operation;
        String key = "matrix";
        List<FrameLayout> sources = new ArrayList<>();
        List<ImageView> images = new ArrayList<>();
        float[] originalAlphas = new float[count];
        for (int i = 0; i < count; i++) {
            FrameLayout view = source(0.25f + i * 0.05f);
            ImageView image = image(view);
            sources.add(view);
            images.add(image);
            originalAlphas[i] = view.getAlpha();
            LevixelSourceViewRegistry.registerSource(key, image, i, view, "source-" + i);
        }
        LevixelSourceViewRegistry.Selection selection = new LevixelSourceViewRegistry.Selection(key, "source-" + clicked, root);
        LevixelSourceViewRegistry.HiddenSource lease = LevixelSourceViewRegistry.hide(selection);
        try {
            selection.allowFallback();
            assertSame(context, images.get(clicked), selection.image());
            // Refresh in reverse order before mutation; fallback order must still
            // be original registration order, not the latest update order.
            for (int i = count - 1; i >= 0; i--) {
                LevixelSourceViewRegistry.registerSource(key, images.get(i), i, sources.get(i), "source-" + i);
            }
            FrameLayout target = sources.get(changed);
            String targetId = "source-" + changed;
            int expected = clicked;
            if ("refresh".equals(operation)) {
                LevixelSourceViewRegistry.registerSource(key, images.get(changed), 24f, target, targetId);
            } else if ("image-gap".equals(operation)) {
                target.removeAllViews();
                LevixelSourceViewRegistry.registerSource(key, null, 12f, target, targetId);
                assertSame(context, clicked == changed ? null : images.get(clicked), selection.image());
                assertSourceAlphas(context, sources, originalAlphas, clicked);
                images.set(changed, image(target));
                LevixelSourceViewRegistry.registerSource(key, images.get(changed), 12f, target, targetId);
            } else {
                if ("remove".equals(operation)) LevixelSourceViewRegistry.unregisterSource(target);
                if ("rebind".equals(operation)) LevixelSourceViewRegistry.registerSource("other-media", images.get(changed), 0f, target, targetId);
                if ("clip".equals(operation)) target.offsetLeftAndRight(600);
                if ("host-hide".equals(operation)) target.setVisibility(View.INVISIBLE);
                if (clicked == changed) expected = count == 1 ? -1 : (changed == 0 ? 1 : 0);
            }
            assertSame(context, expected < 0 ? null : images.get(expected), selection.image());
            assertSourceAlphas(context, sources, originalAlphas, expected);

            if ("clip".equals(operation)) target.offsetLeftAndRight(-600);
            target.setVisibility(View.VISIBLE);
            LevixelSourceViewRegistry.registerSource(key, images.get(changed), 12f, target, targetId);
            if (expected < 0) expected = changed;
            assertSame(context + " after restoration", images.get(expected), selection.image());
            assertSourceAlphas(context, sources, originalAlphas, expected);
            lease.close();
            assertSourceAlphas(context + " after paging away", sources, originalAlphas, -1);
            lease = LevixelSourceViewRegistry.hide(selection);
            assertSame(context + " after paging back", images.get(expected), selection.image());
            assertSourceAlphas(context, sources, originalAlphas, expected);
            for (FrameLayout view : sources) LevixelSourceViewRegistry.unregisterSource(view);
            assertNull(context + " after removing all sources", selection.image());
            assertSourceAlphas(context, sources, originalAlphas, -1);
        } finally {
            lease.close();
            lease.close();
            for (FrameLayout view : sources) {
                LevixelSourceViewRegistry.unregisterSource(view);
                root.removeView(view);
            }
        }
    }

    private void assertSourceAlphas(String context, List<FrameLayout> sources, float[] originalAlphas, int hidden) {
        for (int i = 0; i < sources.size(); i++) {
            assertEquals(context + ", opacity " + i, i == hidden ? 0f : originalAlphas[i], sources.get(i).getAlpha(), 0f);
        }
    }

    private LevixelSourceViewRegistry.HiddenSource hide(LevixelSourceViewRegistry.Selection selection) {
        LevixelSourceViewRegistry.HiddenSource lease = LevixelSourceViewRegistry.hide(selection);
        leases.add(lease);
        return lease;
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
