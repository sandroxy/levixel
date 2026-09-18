package com.sandrox.levixel;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.drawable.BitmapDrawable;
import android.os.Looper;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import androidx.viewpager2.widget.ViewPager2;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.util.ReflectionHelpers;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@LooperMode(LooperMode.Mode.PAUSED)
public final class LevixelViewerLifecycleTest {
    private ActivityController<Activity> activityController;
    private FrameLayout root;
    private FrameLayout container;
    private LevixelViewerOverlayView overlay;
    private final List<String> events = new ArrayList<>();
    private int dismissals;
    private Runnable afterDismiss;

    @Before public void setUp() {
        activityController = Robolectric.buildActivity(Activity.class).setup().visible();
        Activity activity = activityController.get();
        root = new FrameLayout(activity);
        activity.setContentView(root);
        container = new FrameLayout(activity);
        root.addView(container);
        LevixelMediaItem item = new LevixelMediaItem("image", LevixelMediaItem.MediaType.IMAGE,
                "file:///levixel-test.jpg", "file:///levixel-test.jpg");
        overlay = new LevixelViewerOverlayView(activity, Collections.singletonList(item), 0,
                false, "gallery", new LevixelViewerOverlayView.Listener() {
            @Override public void onOverlayDismissed() {
                dismissals++;
                if (afterDismiss != null) afterDismiss.run();
            }
            @Override public void onOverlayIndexChange(int index) {}
            @Override public void onViewerEvent(LevixelViewerEvent event) { events.add(event.type); }
        });
        container.addView(overlay);
        assertTrue(overlay.isAttachedToWindow());
    }

    @After public void tearDown() {
        activityController.pause().stop().destroy();
    }

    @Test public void hostRemovalOfLastChildDoesNotReenterRemoval() {
        container.removeView(overlay);
        assertEquals(0, container.getChildCount());
        assertDismissedOnce();
    }

    @Test public void hostRemovalPreservesFollowingSibling() {
        View sibling = new View(activityController.get());
        container.addView(sibling);
        container.removeView(overlay);
        assertEquals(1, container.getChildCount());
        assertSame(sibling, container.getChildAt(0));
        assertTrue(sibling.isAttachedToWindow());
        assertDismissedOnce();
    }

    @Test public void parentDetachmentDoesNotMutateItsChildren() {
        View sibling = new View(activityController.get());
        container.addView(sibling);
        root.removeView(container);
        assertEquals(2, container.getChildCount());
        assertFalse(overlay.isAttachedToWindow());
        assertFalse(sibling.isAttachedToWindow());
        assertDismissedOnce();
    }

    @Test public void explicitDismissalStillRemovesTheOverlay() {
        overlay.dismissImmediately();
        assertEquals(0, container.getChildCount());
        assertDismissedOnce();
    }

    @Test public void dismissCallbackCanRemoveOldOverlayAndMountReplacement() {
        View replacement = new View(activityController.get());
        afterDismiss = () -> {
            container.removeView(overlay);
            container.addView(replacement);
        };
        container.removeView(overlay);
        assertDismissedOnce();
        assertEquals(1, container.getChildCount());
        assertSame(replacement, container.getChildAt(0));
        assertTrue(replacement.isAttachedToWindow());
    }

    @Test public void dismissalDuringOpeningRestoresTheWholeSource() {
        FrameLayout source = registerSource();
        startOpening();
        assertEquals(0f, source.getAlpha(), 0f);
        overlay.dismissImmediately();
        assertEquals(0.6f, source.getAlpha(), 0f);
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        assertEquals(0.6f, source.getAlpha(), 0f);
        assertEquals(1, dismissals);
    }

    @Test public void normalCloseRestoresSourceAfterItsImageHasBeenReplaced() {
        FrameLayout source = registerSource();
        startOpening();
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        assertTrue(events.contains("opened"));
        ImageView old = (ImageView) source.getChildAt(0);
        old.setVisibility(View.GONE);
        old.setImageDrawable(null);
        ImageView replacement = sourceImage(source);
        LevixelSourceViewRegistry.registerSource(sourceKey(), replacement, 0f, source);
        assertEquals(0f, source.getAlpha(), 0f);

        overlay.requestClose();
        assertEquals(0f, source.getAlpha(), 0f);
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        assertEquals(0.6f, source.getAlpha(), 0f);
        assertEquals(1f, replacement.getAlpha(), 0f);
        assertEquals(1, dismissals);
    }

    @Test public void recyclingDuringOpeningCannotBeRehiddenByAnimationCompletion() {
        FrameLayout source = registerSource();
        startOpening();
        ImageView image = (ImageView) source.getChildAt(0);
        LevixelSourceViewRegistry.registerSource("another-media", image, 0f, source);
        assertEquals(0.6f, source.getAlpha(), 0f);
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        assertEquals(0.6f, source.getAlpha(), 0f);
        overlay.dismissImmediately();
        assertEquals(0.6f, source.getAlpha(), 0f);
    }

    @Test public void hostRemovalRestoresAnOpenSource() {
        FrameLayout source = registerSource();
        startOpening();
        assertEquals(0f, source.getAlpha(), 0f);
        container.removeView(overlay);
        assertEquals(0.6f, source.getAlpha(), 0f);
        Shadows.shadowOf(Looper.getMainLooper()).idle();
        assertEquals(1, dismissals);
        assertEquals(1, Collections.frequency(events, "dismiss"));
    }

    @Test public void pagingRestoresTheOldSourceAndHidesTheNewOne() {
        overlay.dismissImmediately();
        LevixelMediaItem first = new LevixelMediaItem("image", LevixelMediaItem.MediaType.IMAGE,
                "file:///levixel-test.jpg", "file:///levixel-test.jpg");
        LevixelMediaItem next = new LevixelMediaItem("next", LevixelMediaItem.MediaType.IMAGE,
                "file:///levixel-next.jpg", "file:///levixel-next.jpg");
        overlay = new LevixelViewerOverlayView(activityController.get(),
                java.util.Arrays.asList(first, next), 0, false, "gallery", null);
        container.addView(overlay);
        FrameLayout firstSource = registerSource();
        FrameLayout nextSource = new FrameLayout(activityController.get());
        root.addView(nextSource, 0, new FrameLayout.LayoutParams(100, 100));
        nextSource.layout(0, 0, 100, 100);
        LevixelSourceViewRegistry.registerSource(LevixelSharedElementNames.forItem("gallery", next),
                sourceImage(nextSource), 0f, nextSource);
        startOpening();
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        assertEquals(0f, firstSource.getAlpha(), 0f);
        assertEquals(1f, nextSource.getAlpha(), 0f);

        ViewPager2 pager = ReflectionHelpers.getField(overlay, "viewPager");
        pager.setCurrentItem(1, false);
        assertEquals(0.6f, firstSource.getAlpha(), 0f);
        assertEquals(0f, nextSource.getAlpha(), 0f);
        overlay.dismissImmediately();
        assertEquals(1f, nextSource.getAlpha(), 0f);
    }

    @Test public void clickedSourceRemainsSelectedAcrossPagingAndSiblingRegistration() {
        overlay.dismissImmediately();
        LevixelMediaItem first = new LevixelMediaItem("image", LevixelMediaItem.MediaType.IMAGE,
                "file:///levixel-test.jpg", "file:///levixel-test.jpg");
        LevixelMediaItem next = new LevixelMediaItem("next", LevixelMediaItem.MediaType.IMAGE,
                "file:///levixel-next.jpg", "file:///levixel-next.jpg");
        overlay = new LevixelViewerOverlayView(activityController.get(), java.util.Arrays.asList(first, next),
                null, 0, false, "gallery", Collections.emptyList(), LevixelActionLayout.LIST, false, "clicked", null);
        container.addView(overlay);
        FrameLayout sibling = registerSource();
        FrameLayout clicked = new FrameLayout(activityController.get());
        root.addView(clicked, 0, new FrameLayout.LayoutParams(100, 100));
        clicked.layout(100, 0, 200, 100);
        clicked.setAlpha(0.8f);
        LevixelSourceViewRegistry.registerSource(sourceKey(), sourceImage(clicked), 12f, clicked, "clicked");
        startOpening();
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        assertEquals(0f, clicked.getAlpha(), 0f);
        assertEquals(0.6f, sibling.getAlpha(), 0f);
        ViewPager2 pager = ReflectionHelpers.getField(overlay, "viewPager");
        pager.setCurrentItem(1, false);
        assertEquals(0.8f, clicked.getAlpha(), 0f);
        LevixelSourceViewRegistry.registerSource(sourceKey(), (ImageView) sibling.getChildAt(0), 0f, sibling);
        pager.setCurrentItem(0, false);
        assertEquals(0f, clicked.getAlpha(), 0f);
        assertEquals(0.6f, sibling.getAlpha(), 0f);
        overlay.requestClose();
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        assertEquals(0.8f, clicked.getAlpha(), 0f);
        assertEquals(0.6f, sibling.getAlpha(), 0f);
    }

    @Test public void viewerKeepsItsSnapshotAndRestoresSourcesForEveryDemoOperation() {
        overlay.dismissImmediately();
        for (int clicked = 0; clicked < 3; clicked++) {
            for (String operation : new String[] {"none", "prepend", "reorder", "replace-images", "refresh-cover", "remove-thumbnail", "remove-sources"}) {
                String context = "source=" + clicked + ", " + operation;
                List<LevixelMediaItem> hostItems = new ArrayList<>();
                hostItems.add(new LevixelMediaItem("image", LevixelMediaItem.MediaType.IMAGE, "file:///levixel-test.jpg", "file:///levixel-test.jpg"));
                hostItems.add(new LevixelMediaItem("next", LevixelMediaItem.MediaType.IMAGE, "file:///levixel-next.jpg", "file:///levixel-next.jpg"));
                List<FrameLayout> sources = new ArrayList<>();
                float[] alphas = {0.8f, 0.6f, 1f};
                for (int i = 0; i < 3; i++) {
                    FrameLayout view = new FrameLayout(activityController.get());
                    root.addView(view, 0, new FrameLayout.LayoutParams(100, 100));
                    view.layout(i * 120, 0, i * 120 + 100, 100);
                    view.setAlpha(alphas[i]);
                    sources.add(view);
                    LevixelSourceViewRegistry.registerSource(sourceKey(), sourceImage(view), i * 8f, view, "source-" + i);
                }
                List<LevixelViewerEvent> recorded = new ArrayList<>();
                overlay = new LevixelViewerOverlayView(activityController.get(), hostItems, null, 0, false,
                        "gallery", Collections.emptyList(), LevixelActionLayout.LIST, false, "source-" + clicked,
                        new LevixelViewerOverlayView.Listener() {
                            @Override public void onOverlayDismissed() { }
                            @Override public void onOverlayIndexChange(int index) { }
                            @Override public void onViewerEvent(LevixelViewerEvent event) { recorded.add(event); }
                        });
                container.addView(overlay);
                try {
                    startOpening();
                    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
                    assertViewerSourceAlphas(context, sources, alphas, clicked);
                    int expected = clicked;
                    if ("prepend".equals(operation)) hostItems.add(0, new LevixelMediaItem("history", LevixelMediaItem.MediaType.IMAGE, "file:///history.jpg", "file:///history.jpg"));
                    if ("reorder".equals(operation)) Collections.reverse(hostItems);
                    if ("replace-images".equals(operation)) {
                        for (int i = 0; i < 3; i++) {
                            FrameLayout view = sources.get(i);
                            view.removeAllViews();
                            LevixelSourceViewRegistry.registerSource(sourceKey(), sourceImage(view), i * 8f, view, "source-" + i);
                        }
                    }
                    if ("refresh-cover".equals(operation)) LevixelSourceViewRegistry.registerSource(sourceKey(), (ImageView) sources.get(0).getChildAt(0), 24f, sources.get(0), "source-0");
                    if ("remove-thumbnail".equals(operation)) {
                        LevixelSourceViewRegistry.unregisterSource(sources.get(1));
                        root.removeView(sources.get(1));
                        if (clicked == 1) expected = 0;
                    }
                    if ("remove-sources".equals(operation)) {
                        for (FrameLayout source : sources) {
                            LevixelSourceViewRegistry.unregisterSource(source);
                            root.removeView(source);
                        }
                        expected = -1;
                    }
                    assertViewerSourceAlphas(context, sources, alphas, expected);
                    ViewPager2 pager = ReflectionHelpers.getField(overlay, "viewPager");
                    assertEquals(context, 2, pager.getAdapter().getItemCount());
                    pager.setCurrentItem(1, false);
                    assertViewerSourceAlphas(context + " after paging away", sources, alphas, -1);
                    pager.setCurrentItem(0, false);
                    assertViewerSourceAlphas(context + " after paging back", sources, alphas, expected);
                    overlay.requestClose();
                    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
                    assertViewerSourceAlphas(context + " after closing", sources, alphas, -1);
                    List<String> pageIds = new ArrayList<>();
                    int opened = 0, dismissed = 0;
                    for (LevixelViewerEvent event : recorded) {
                        if ("indexChange".equals(event.type)) pageIds.add((String) event.payload.get("itemId"));
                        if ("opened".equals(event.type)) opened++;
                        if ("dismiss".equals(event.type)) dismissed++;
                    }
                    assertEquals(context, java.util.Arrays.asList("image", "next", "image"), pageIds);
                    assertEquals(context, 1, opened);
                    assertEquals(context, 1, dismissed);
                    assertNull(context, overlay.getParent());
                } finally {
                    overlay.dismissImmediately();
                    for (FrameLayout source : sources) {
                        LevixelSourceViewRegistry.unregisterSource(source);
                        root.removeView(source);
                    }
                }
            }
        }
    }

    private void assertViewerSourceAlphas(String context, List<FrameLayout> sources, float[] original, int hidden) {
        for (int i = 0; i < sources.size(); i++) {
            assertEquals(context + ", opacity " + i, i == hidden ? 0f : original[i], sources.get(i).getAlpha(), 0f);
        }
    }

    private FrameLayout registerSource() {
        FrameLayout source = new FrameLayout(activityController.get());
        root.addView(source, 0, new FrameLayout.LayoutParams(100, 100));
        source.layout(0, 0, 100, 100);
        source.setAlpha(0.6f);
        LevixelSourceViewRegistry.registerSource(sourceKey(), sourceImage(source), 0f, source);
        return source;
    }

    private ImageView sourceImage(FrameLayout source) {
        ImageView image = new ImageView(activityController.get());
        image.setImageDrawable(new BitmapDrawable(image.getResources(),
                Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)));
        source.addView(image, new FrameLayout.LayoutParams(100, 100));
        image.layout(0, 0, 100, 100);
        return image;
    }

    private String sourceKey() {
        return LevixelSharedElementNames.forItem("gallery", new LevixelMediaItem("image",
                LevixelMediaItem.MediaType.IMAGE, "file:///levixel-test.jpg", "file:///levixel-test.jpg"));
    }

    private void startOpening() {
        root.measure(View.MeasureSpec.makeMeasureSpec(500, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(500, View.MeasureSpec.EXACTLY));
        root.layout(0, 0, 500, 500);
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(20));
    }

    private void assertDismissedOnce() {
        overlay.dismissImmediately();
        overlay.requestClose();
        Shadows.shadowOf(Looper.getMainLooper()).idle();
        assertEquals(1, dismissals);
        assertEquals(Collections.singletonList("dismiss"), events);
    }
}
