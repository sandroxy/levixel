package com.sandrox.levixel.reactnative

import android.app.Activity
import android.graphics.Bitmap
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.sandrox.levixel.LevixelViewerOverlayView
import expo.modules.kotlin.viewevent.ViewEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ActivityController
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.annotation.RealObject
import org.robolectric.util.ReflectionHelpers
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], shadows = [LevixelViewCommandsTest.JSEventSink::class])
@LooperMode(LooperMode.Mode.PAUSED)
class LevixelViewCommandsTest {
    private lateinit var activity: ActivityController<Activity>
    private lateinit var root: FrameLayout
    private lateinit var view: LevixelView
    private lateinit var imageUrl: String
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @Before fun setUp() {
        JSEventSink.names.clear()
        activity = Robolectric.buildActivity(Activity::class.java).setup().visible()
        root = FrameLayout(activity.get())
        activity.get().setContentView(root)
        view = LevixelView(activity.get())
        root.addView(view, FrameLayout.LayoutParams(0, 0))
        val image = activity.get().cacheDir.resolve("commands.png")
        image.outputStream().use {
            Bitmap.createBitmap(40, 40, Bitmap.Config.ARGB_8888)
                .compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        imageUrl = image.toURI().toString()
    }

    @After fun tearDown() {
        overlay()?.dismissImmediately()
        scope.cancel()
        activity.pause().stop().destroy()
        idle()
    }

    @Test fun closeWithoutAnOverlayCompletesImmediately() {
        assertTrue(close().isCompleted)
        assertFalse(view.retry())
    }

    @Test fun controllerReadinessWaitsForAttachmentAndIsEmittedOncePerAttachment() {
        root.removeView(view)
        view.isController = true
        view.commitSourceBinding()
        assertTrue(JSEventSink.names.isEmpty())
        root.addView(view)
        assertEquals(listOf("onControllerReady"), JSEventSink.names)
        view.commitSourceBinding()
        assertEquals(1, JSEventSink.names.size)
        root.removeView(view)
        root.addView(view)
        assertEquals(listOf("onControllerReady", "onControllerReady"), JSEventSink.names)
    }

    @Test fun controllerPropsAppliedAfterAttachmentAlsoSignalReadiness() {
        assertTrue(view.isAttachedToWindow)
        assertTrue(JSEventSink.names.isEmpty())
        view.isController = true
        view.commitSourceBinding()
        assertEquals(listOf("onControllerReady"), JSEventSink.names)
    }

    @Test fun concurrentCloseCallsWaitForActualDismissal() {
        open("first")
        val first = close()
        val second = close()
        assertFalse(first.isCompleted)
        assertFalse(second.isCompleted)
        assertNotNull(overlay())
        idle()
        assertTrue(first.isCompleted && !first.isCancelled)
        assertTrue(second.isCompleted && !second.isCancelled)
        assertNull(overlay())
    }

    @Test fun detachingTheControllerCompletesAnOutstandingClose() {
        open("first")
        val closing = close()
        root.removeView(view)
        idle()
        assertTrue(closing.isCompleted && !closing.isCancelled)
        assertNull(overlay())
    }

    @Test fun replacementCompletesOnlyThePreviousSessionsClose() {
        open("first")
        val first = close()
        open("second")
        assertTrue(first.isCompleted && !first.isCancelled)
        assertNotNull(overlay())
        val second = close()
        assertFalse(second.isCompleted)
        idle()
        assertTrue(second.isCompleted && !second.isCancelled)
        assertNull(overlay())
    }

    @Test fun cancellingOneCallerDoesNotCancelOtherCloseCallers() {
        open("first")
        val first = close()
        val second = close()
        first.cancel()
        assertFalse(second.isCompleted)
        idle()
        assertTrue(first.isCancelled)
        assertTrue(second.isCompleted && !second.isCancelled)
        assertNull(overlay())
    }

    private fun close() = scope.async(start = CoroutineStart.UNDISPATCHED) { view.close() }

    private fun open(requestId: String) {
        view.open(mapOf(
            "requestId" to requestId, "galleryId" to "commands", "index" to 0,
            "items" to listOf(mapOf("id" to "image", "type" to "image", "url" to imageUrl))
        ))
        val decor = activity.get().window.decorView
        val size = View.MeasureSpec.makeMeasureSpec(500, View.MeasureSpec.EXACTLY)
        decor.measure(size, size)
        decor.layout(0, 0, 500, 500)
        idle()
    }

    private fun overlay(): LevixelViewerOverlayView? {
        val decor = activity.get().window.decorView as ViewGroup
        return (0 until decor.childCount).map(decor::getChildAt)
            .filterIsInstance<LevixelViewerOverlayView>().singleOrNull()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))

    // Only the outbound JS event bridge is absent from this JVM test. Overlay
    // dismissal, controller detach, and suspended close callers all run normally.
    @Implements(ViewEvent::class, isInAndroidSdk = false)
    class JSEventSink {
        @RealObject private lateinit var event: ViewEvent<*>
        @Implementation fun invoke(payload: Any?) {
            names.add(ReflectionHelpers.getField(event, "name"))
        }
        companion object { val names = mutableListOf<String>() }
    }
}
