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
