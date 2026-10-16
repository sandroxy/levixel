package com.sandrox.levixel.flutter;

import static org.junit.Assert.*;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.os.Looper;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewConfiguration;
import android.widget.ImageView;
import com.sandrox.levixel.LevixelViewerOverlayView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
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

/** Real bridge and viewer; only the Dart endpoint and Flutter rendering are absent. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@LooperMode(LooperMode.Mode.PAUSED)
public final class LevixelSourceUpdatesTest {
    private final RecordingMessenger messenger = new RecordingMessenger();
    private ActivityController<Activity> activityController;
    private LevixelPlugin plugin;
    private ViewGroup host;
    private Object session;
    private LevixelViewerOverlayView viewer;
    private byte[] preview;

    @Before public void setUp() {
        activityController = Robolectric.buildActivity(Activity.class).setup().visible();
        Activity activity = activityController.get();
        // An attached FlutterView is required by the real prepare/open path. No
        // FlutterEngine is needed for these method-channel and native-view tests.
        activity.setContentView(new FlutterView(activity) {
            @Override public BinaryMessenger getBinaryMessenger() { return messenger; }
        });
        host = (ViewGroup) activity.getWindow().getDecorView();
        plugin = new LevixelPlugin();
        ReflectionHelpers.setField(plugin, "activity", activity);
        ReflectionHelpers.setField(plugin, "messenger", messenger);
        ReflectionHelpers.setField(plugin, "channel", new MethodChannel(messenger, "sandrox_levixel"));
        Bitmap bitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888);
        bitmap.eraseColor(Color.RED);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes));
        bitmap.recycle();
        preview = bytes.toByteArray();
        call("prepare", fields(
                "galleryId", "gallery", "sourceId", "selected", "index", 0,
                "theme", "dark", "actionLayout", "list", "actionListIcons", false,
                "items", Arrays.asList(
                        fields("id", "first", "type", "image", "url", "file:///levixel-first.jpg"),
                        fields("id", "second", "type", "image", "url", "file:///levixel-second.jpg")),
                "actions", Collections.singletonList(fields("id", "inspect", "label", "Inspect",
                        "disabled", false, "destructive", false)),
                "sources", Collections.emptyList()));
        session = ReflectionHelpers.getField(plugin, "session");
        // Exercise updates before native presentation as well as after opening.
        update(source("selected", "first", 20), source("sibling", "first", 160));
        layoutHost();
        call("open", fields());
        viewer = ReflectionHelpers.getField(session, "overlay");
        assertNotNull(viewer);
        layoutHost();
        settle();
        assertEquals(1, eventCount("opened"));
        assertFalse(viewer.isClosing());
        assertEquals(0f, sources().get("selected").getAlpha(), 0f);
        assertEquals(1f, sources().get("sibling").getAlpha(), 0f);
    }

    @After public void tearDown() {
        if (plugin != null) plugin.onDetachedFromActivity();
        if (activityController != null) activityController.pause().stop().destroy();
    }

    @Test public void backRejectsLateUpdatesBeforeTheDismissCallback() {
        assertTrue(viewer.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)));
        assertLateUpdatesIgnored();
        assertDismissalRestoresSources();
    }

    @Test public void committedDragRejectsLateUpdatesBeforeTheDismissCallback() {
        drag(.30f, MotionEvent.ACTION_UP);
        assertLateUpdatesIgnored();
        assertDismissalRestoresSources();
    }

    @Test public void shortDragReleaseStillAcceptsSourceUpdates() {
        drag(.02f, MotionEvent.ACTION_UP);
        assertOpenViewerAcceptsSourceUpdates();
        viewer.requestClose();
        assertDismissalRestoresSources();
    }

    @Test public void systemCancellationPastDismissThresholdStillAcceptsSourceUpdates() {
        View target = drag(.30f, MotionEvent.ACTION_CANCEL);
        assertFalse(viewer.isClosing());
        assertFalse(ReflectionHelpers.<Boolean>getField(viewer, "dragging"));
        assertNull(ReflectionHelpers.getField(viewer, "velocityTracker"));
        assertNull(ReflectionHelpers.getField(viewer, "dragTarget"));
        assertNull(ReflectionHelpers.getField(viewer, "dragPageView"));
        assertEquals(0, eventCount("dismiss"));
        assertOpenViewerAcceptsSourceUpdates();
        assertEquals(0f, target.getTranslationY(), .001f);
        assertEquals(1f, target.getScaleX(), .001f);
        assertEquals(1f, target.getScaleY(), .001f);
        viewer.requestClose();
        assertDismissalRestoresSources();
    }

    private void assertOpenViewerAcceptsSourceUpdates() {
        assertFalse(viewer.isClosing());
        update(source("selected", "first", 80), source("sibling", "first", 160));
        assertEquals(80f, sources().get("selected").getX(), 0f);
        assertEquals(0f, sources().get("selected").getAlpha(), 0f);
        settle();
        assertFalse(viewer.isClosing());
        assertEquals(0, eventCount("dismiss"));
        update(source("sibling", "first", 180));
        assertFalse(sources().containsKey("selected"));
        assertEquals(0f, sources().get("sibling").getAlpha(), 0f);
    }

    @Test public void backThatOnlyClosesActionsStillAcceptsSourceUpdates() {
        openActions();
        viewer.handleBack();
        assertFalse(viewer.isClosing());
        update(source("selected", "first", 80), source("sibling", "first", 160));
        assertEquals(80f, sources().get("selected").getX(), 0f);
        settle();
        assertNull(ReflectionHelpers.getField(viewer, "actionSheet"));
        assertFalse(viewer.isClosing());
        assertEquals(0, eventCount("dismiss"));
        assertEquals(0f, sources().get("selected").getAlpha(), 0f);
        viewer.handleBack();
        assertLateUpdatesIgnored();
        assertDismissalRestoresSources();
    }

    @Test public void closingTheViewerWithActionsOpenRejectsLateUpdates() {
        openActions();
        viewer.requestClose();
        assertLateUpdatesIgnored();
        assertDismissalRestoresSources();
    }

    private void assertLateUpdatesIgnored() {
        assertTrue(viewer.isClosing());
        assertSame(viewer, ReflectionHelpers.getField(session, "overlay"));
        assertFalse("The native dismissal callback must not have fired yet",
                ReflectionHelpers.<Boolean>getField(session, "closing"));
        assertEquals(0, eventCount("dismiss"));
        Map<String, ViewGroup> original = new LinkedHashMap<>(sources());
        ViewGroup selected = original.get("selected");
        float originalX = selected.getX();
        Drawable originalImage = ((ImageView) selected.getChildAt(0)).getDrawable();
        int visibilityCount = visibilityCount();

        // Geometry refresh, media replacement/new registration, and removal all
        // arrive after native geometry sampling but before bridge completion.
        update(source("selected", "first", 240), source("sibling", "first", 160));
        assertEquals(originalX, selected.getX(), 0f);
        assertSame(originalImage, ((ImageView) selected.getChildAt(0)).getDrawable());
        update(source("selected", "second", 40), source("new-source", "first", 300));
        assertEquals(original, sources());
        update();
        assertEquals(original, sources());
        assertEquals(visibilityCount, visibilityCount());
        assertEquals(0f, selected.getAlpha(), 0f);
        assertEquals(1f, original.get("sibling").getAlpha(), 0f);
        assertSame(host, selected.getParent());
    }

    private void assertDismissalRestoresSources() {
        settle();
        assertEquals(1, eventCount("dismiss"));
        assertNull(ReflectionHelpers.getField(session, "overlay"));
        assertTrue(viewer.isClosing());
        for (ViewGroup source : sources().values()) assertEquals(1f, source.getAlpha(), 0f);
        Map<String, ViewGroup> original = new LinkedHashMap<>(sources());
        update();
        assertEquals("Completed sessions must also reject source updates", original, sources());
        call("finish", fields());
        for (ViewGroup source : original.values()) assertNull(source.getParent());
        assertNull(ReflectionHelpers.getField(plugin, "session"));
    }

    private View drag(float distance, int terminalAction) {
        long time = SystemClock.uptimeMillis();
        float start = viewer.getHeight() * .35f;
        float engaged = start + viewer.getHeight() * .08f;
        float end = engaged + viewer.getHeight() * distance;
        touch(time, time, MotionEvent.ACTION_DOWN, start);
        touch(time, time + 100, MotionEvent.ACTION_MOVE, engaged);
        assertTrue("The native viewer must actually enter its drag path",
                ReflectionHelpers.<Boolean>getField(viewer, "dragging"));
        assertFalse(viewer.isClosing());
        touch(time, time + 300, MotionEvent.ACTION_MOVE, end);
        View target = ReflectionHelpers.getField(viewer, "dragTarget");
        assertNotNull(target);
        assertEquals(viewer.getHeight() * distance, target.getTranslationY(), .001f);
        assertFalse(viewer.isClosing());
        touch(time, time + 700, terminalAction, end);
        return target;
    }

    private void openActions() {
        long time = SystemClock.uptimeMillis();
        // Avoid the central retry control if the deliberately absent full image
        // has finished failing while the source preview remains displayed.
        float y = viewer.getHeight() * .25f;
        touch(time, time, MotionEvent.ACTION_DOWN, y);
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(
                Duration.ofMillis(ViewConfiguration.getLongPressTimeout() + 500));
        touch(time, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, y);
        assertNotNull(ReflectionHelpers.getField(viewer, "actionSheet"));
        assertFalse(viewer.isClosing());
    }

    private void touch(long down, long time, int action, float y) {
        MotionEvent event = MotionEvent.obtain(down, time, action, viewer.getWidth() * .5f, y, 0);
        try { viewer.dispatchTouchEvent(event); }
        finally { event.recycle(); }
    }

    @SafeVarargs private final void update(Map<String, Object>... sources) {
        call("updateSources", fields("sources", Arrays.asList(sources)));
    }

    private Map<String, Object> source(String id, String item, int x) {
        return fields("sourceId", id, "itemId", item, "pixelRatio", 1,
                "frame", Arrays.asList(x, 20, 100, 100), "clip", Arrays.asList(x, 20, 100, 100),
                "cornerRadius", 12, "opacity", .6, "fit", "cover", "png", preview);
    }

    private Map<String, ViewGroup> sources() { return ReflectionHelpers.getField(session, "sources"); }

    private void call(String method, Map<String, Object> args) {
        args.put("requestId", "request");
        int[] successes = {0};
        plugin.onMethodCall(new MethodCall(method, args), new MethodChannel.Result() {
            @Override public void success(Object value) { successes[0]++; }
            @Override public void error(String code, String message, Object details) {
                fail(method + ": " + code + ": " + message);
            }
            @Override public void notImplemented() { fail("Unimplemented " + method); }
        });
        assertEquals(method + " must reply exactly once", 1, successes[0]);
    }

    private int eventCount(String type) {
        int count = 0;
        for (MethodCall call : messenger.calls) {
            if (call.method.equals("event") && type.equals(((Map<?, ?>) call.arguments).get("type"))) count++;
        }
        return count;
    }

    private int visibilityCount() {
        int count = 0;
        for (MethodCall call : messenger.calls) if (call.method.equals("visibility")) count++;
        return count;
    }

    private void layoutHost() {
        host.measure(View.MeasureSpec.makeMeasureSpec(500, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY));
        host.layout(0, 0, 500, 800);
    }

    private void settle() { Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1)); }

    private static Map<String, Object> fields(Object... fields) {
        Map<String, Object> value = new LinkedHashMap<>();
        for (int i = 0; i < fields.length; i += 2) value.put((String) fields[i], fields[i + 1]);
        return value;
    }

    private static final class RecordingMessenger implements BinaryMessenger {
        final List<MethodCall> calls = new ArrayList<>();
        @Override public void send(String channel, ByteBuffer message) { send(channel, message, null); }
        @Override public void send(String channel, ByteBuffer message, BinaryReply callback) {
            ByteBuffer readable = message.duplicate();
            readable.flip();
            calls.add(StandardMethodCodec.INSTANCE.decodeMethodCall(readable));
            if (callback != null) {
                ByteBuffer reply = StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(null);
                reply.flip();
                callback.reply(reply);
            }
        }
        @Override public void setMessageHandler(String channel, BinaryMessageHandler handler) { }
    }
}
