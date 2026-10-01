package com.sandrox.tests.levixel_source_host;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import android.app.Instrumentation;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;

import androidx.test.core.app.ActivityScenario;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;

import org.junit.Test;

import java.io.File;
import java.io.FileOutputStream;

public final class NativeGestureTest {
    private final Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
    private final UiDevice device = UiDevice.getInstance(instrumentation);
    private final File screenshots = new File(instrumentation.getTargetContext().getExternalFilesDir(null), "gestures");

    @Test
    public void nativeTouchesPreserveMediaAndRestoreSources() throws Exception {
        assertTrue(screenshots.isDirectory() || screenshots.mkdirs());
        try (ActivityScenario<MainActivity> activity = ActivityScenario.launch(MainActivity.class)) {
            openFirst();
            assertTrue(device.swipe(x(0.85), y(0.5), x(0.15), y(0.5), 60));
            awaitImage(false, "paged-second");
            assertTrue(device.swipe(x(0.5), y(0.5), x(0.5), y(0.5), 180));
            UiObject2 action = device.wait(Until.findObject(By.desc("Inspect")), 10000);
            assertNotNull("Long press must show native actions", action);
            capture("actions");
            action.click();
            assertTrue(device.wait(Until.gone(By.desc("Inspect")), 10000));
            dismissDrag();
            awaitStatus("Dismiss 1 second 1 | Action inspect second 1");

            openFirst();
            tap();
            SystemClock.sleep(80);
            tap();
            device.waitForIdle();
            assertTrue(device.swipe(x(0.5), y(0.5), x(0.5), y(0.78), 80));
            awaitImage(true, "double-tap-pan");
            shrinkToFit();
            dismissDrag();
            awaitStatus("Dismiss 2 first 0 | Action inspect second 1");

            openFirst();
            pinch(0.10f, 0.35f);
            device.waitForIdle();
            assertTrue(device.swipe(x(0.5), y(0.5), x(0.5), y(0.78), 80));
            awaitImage(true, "pinch-pan");
            shrinkToFit();
            tap();
            awaitStatus("Dismiss 3 first 0 | Action inspect second 1");
            capture("restored-sources");
        } finally {
            capture("final-state");
            device.dumpWindowHierarchy(new File(screenshots, "hierarchy.xml"));
        }
    }

    private void openFirst() throws Exception {
        UiObject2 source = device.wait(Until.findObject(By.desc("Open first")), 15000);
        assertNotNull("Flutter thumbnail must be restored and accessible", source);
        source.click();
        awaitImage(true, "opened-first");
    }

    private void dismissDrag() {
        assertTrue(device.swipe(x(0.5), y(0.5), x(0.5), y(0.92), 80));
    }

    private void shrinkToFit() throws Exception {
        // Android can end scale recognition before the fingers meet. Check the
        // visible 4:3 fixture instead of assuming one pinch reaches minimum zoom.
        for (int attempt = 0; attempt < 4; attempt++) {
            pinch(0.42f, 0.02f);
            device.waitForIdle();
            Bitmap bitmap = instrumentation.getUiAutomation().takeScreenshot();
            if (bitmap == null) continue;
            int height = 0;
            for (int row = 0; row < bitmap.getHeight(); row++) {
                int pixel = bitmap.getPixel((int) (bitmap.getWidth() * 0.08), row);
                if (Color.red(pixel) > 150 && Color.blue(pixel) < 110) height++;
            }
            double expected = bitmap.getWidth() * 0.75;
            bitmap.recycle();
            if (Math.abs(height - expected) <= expected * 0.02) {
                capture("restored-image-fit");
                return;
            }
        }
        capture("missing-image-fit");
        fail("Pinch gestures must restore the full-width 4:3 image before dismissal");
    }

    private void awaitStatus(String expected) {
        assertTrue("Native events must retain the opening media identity: " + expected,
                device.wait(Until.hasObject(By.desc(expected)), 10000));
    }

    private void awaitImage(boolean red, String name) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 15000;
        do {
            Bitmap bitmap = instrumentation.getUiAutomation().takeScreenshot();
            if (bitmap != null) {
                int pixel = bitmap.getPixel((int) (bitmap.getWidth() * 0.08), bitmap.getHeight() / 2);
                boolean matches = red ? Color.red(pixel) > 150 && Color.blue(pixel) < 110
                        : Color.blue(pixel) > 150 && Color.red(pixel) < 100;
                bitmap.recycle();
                if (matches) { capture(name); return; }
            }
            SystemClock.sleep(100);
        } while (SystemClock.elapsedRealtime() < deadline);
        capture("missing-" + name);
        fail("The native image must cover a point outside the Flutter thumbnails: " + name);
    }

    private void capture(String name) throws Exception {
        Bitmap bitmap = instrumentation.getUiAutomation().takeScreenshot();
        if (bitmap == null) return;
        try (FileOutputStream output = new FileOutputStream(new File(screenshots, name + ".png"))) {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
        } finally { bitmap.recycle(); }
    }

    private int x(double value) { return (int) (device.getDisplayWidth() * value); }
    private int y(double value) { return (int) (device.getDisplayHeight() * value); }

    private void tap() {
        long time = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(time, time, MotionEvent.ACTION_DOWN, x(0.5), y(0.5), 0);
        MotionEvent up = MotionEvent.obtain(time, time + 20, MotionEvent.ACTION_UP, x(0.5), y(0.5), 0);
        try { instrumentation.sendPointerSync(down); instrumentation.sendPointerSync(up); }
        finally { down.recycle(); up.recycle(); }
    }

    private void pinch(float start, float end) {
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[2];
        MotionEvent.PointerCoords[] coordinates = new MotionEvent.PointerCoords[2];
        for (int i = 0; i < 2; i++) {
            properties[i] = new MotionEvent.PointerProperties();
            properties[i].id = i; properties[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            coordinates[i] = new MotionEvent.PointerCoords();
            coordinates[i].pressure = 1; coordinates[i].size = 1; coordinates[i].y = y(0.5);
        }
        long down = SystemClock.uptimeMillis();
        for (int step = 0; step <= 40; step++) {
            float distance = start + (end - start) * step / 40f;
            coordinates[0].x = x(0.5 - distance); coordinates[1].x = x(0.5 + distance);
            if (step == 0) {
                sendPointers(down, MotionEvent.ACTION_DOWN, 1, properties, coordinates);
                sendPointers(down, MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, properties, coordinates);
            } else {
                sendPointers(down, MotionEvent.ACTION_MOVE, 2, properties, coordinates);
            }
            SystemClock.sleep(8);
        }
        sendPointers(down, MotionEvent.ACTION_POINTER_UP | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, properties, coordinates);
        sendPointers(down, MotionEvent.ACTION_UP, 1, properties, coordinates);
    }

    private void sendPointers(long down, int action, int count,
            MotionEvent.PointerProperties[] properties, MotionEvent.PointerCoords[] coordinates) {
        MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, count,
                properties, coordinates, 0, 0, 1, 1, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0);
        try { instrumentation.sendPointerSync(event); }
        finally { event.recycle(); }
    }
}
