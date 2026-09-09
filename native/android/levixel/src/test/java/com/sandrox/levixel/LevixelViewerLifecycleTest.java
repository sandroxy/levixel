package com.sandrox.levixel;

import android.app.Activity;
import android.os.Looper;
import android.view.View;
import android.widget.FrameLayout;
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

    private void assertDismissedOnce() {
        overlay.dismissImmediately();
        overlay.requestClose();
        Shadows.shadowOf(Looper.getMainLooper()).idle();
        assertEquals(1, dismissals);
        assertEquals(Collections.singletonList("dismiss"), events);
    }
}
