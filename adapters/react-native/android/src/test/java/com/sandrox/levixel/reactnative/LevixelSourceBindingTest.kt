package com.sandrox.levixel.reactnative

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.FrameLayout
import android.widget.ImageView
import com.sandrox.levixel.LevixelSourceViewRegistry
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
import org.robolectric.annotation.LooperMode
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@LooperMode(LooperMode.Mode.PAUSED)
class LevixelSourceBindingTest {
    private lateinit var activity: ActivityController<Activity>
    private lateinit var root: FrameLayout
    private lateinit var source: FrameLayout
    private lateinit var loader: FrameLayout
    private lateinit var first: ImageView
    private lateinit var second: ImageView
    private lateinit var binding: LevixelSourceBinding
    private val pressed = mutableListOf<String>()

    @Before fun setUp() {
        activity = Robolectric.buildActivity(Activity::class.java).setup().visible()
        root = FrameLayout(activity.get())
        activity.get().setContentView(root)
        source = FrameLayout(activity.get())
        binding = LevixelSourceBinding(source, pressed::add)
        root.addView(source, FrameLayout.LayoutParams(100, 100))
        loader = FrameLayout(activity.get())
        source.addView(loader, FrameLayout.LayoutParams(100, 100))
        first = image()
        second = image().apply { visibility = View.GONE; setImageDrawable(null) }
        layout()
        binding.update("gallery/media", "media", 8f)
    }

    @After fun tearDown() {
        activity.pause().stop().destroy()
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        assertNull(LevixelSourceViewRegistry.find("gallery/other"))
    }

    @Test fun tapUsesTheStableSourceBeforeAndAfterAnInternalSwap() {
        tap()
        swap(first, second)
        draw()
        assertSame(second, LevixelSourceViewRegistry.find("gallery/media"))
        assertNull(first.transitionName)
        assertFalse(first.isClickable)
        assertFalse(second.isClickable)
        assertTrue(source.isClickable)
        tap()
        assertEquals(listOf("media", "media"), pressed)
    }

    @Test fun tapRefreshesAnImageSwapThatHasNotDrawnYet() {
        swap(first, second)
        // No prop update, layout or pre-draw between the loader swap and tap.
        tap()
        assertSame(second, LevixelSourceViewRegistry.find("gallery/media"))
        assertEquals(listOf("media"), pressed)
    }

    @Test fun asynchronousDrawableArrivalDoesNotRequireAParentLayout() {
        first.setImageDrawable(null)
        draw()
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        tap() // A not-yet-loaded thumbnail still has a valid media identity.
        first.setImageDrawable(ColorDrawable(Color.BLUE))
        draw()
        assertSame(first, LevixelSourceViewRegistry.find("gallery/media"))
        assertEquals(listOf("media"), pressed)
    }

    @Test fun crossfadePrefersTheDisplayedLayerAndIgnoresTheHiddenSourceAlpha() {
        second.visibility = View.VISIBLE
        second.setImageDrawable(ColorDrawable(Color.BLUE))
        second.alpha = 0.2f
        first.alpha = 0.8f
        draw()
        assertSame(first, LevixelSourceViewRegistry.find("gallery/media"))
        source.alpha = 0f // Viewer-owned hiding must not lose its own source.
        first.alpha = 0.2f
        second.alpha = 0.8f
        draw()
        assertSame(second, LevixelSourceViewRegistry.find("gallery/media"))
    }

    @Test fun zeroAlphaOrHiddenLoaderIsNotATransitionAnchor() {
        loader.alpha = 0f
        draw()
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        loader.alpha = 1f
        loader.visibility = View.INVISIBLE
        draw()
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        loader.visibility = View.VISIBLE
        draw()
        assertSame(first, LevixelSourceViewRegistry.find("gallery/media"))
    }

    @Test fun listReuseReplacesIdentityAndRemovedItemsCannotOpen() {
        binding.update("gallery/other", "other", 0f)
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        assertSame(first, LevixelSourceViewRegistry.find("gallery/other"))
        tap()
        assertEquals(listOf("other"), pressed)
        binding.update(null, null, 0f)
        assertNull(LevixelSourceViewRegistry.find("gallery/other"))
        assertFalse(source.isClickable)
        source.performClick() // Even a queued/programmatic click cannot open it.
        assertEquals(listOf("other"), pressed)
    }

    @Test fun recyclingDuringATapDoesNotOpenTheReplacementItem() {
        touch(MotionEvent.ACTION_DOWN)
        binding.update("gallery/other", "other", 0f)
        touch(MotionEvent.ACTION_UP)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(pressed.isEmpty())
        tap()
        assertEquals(listOf("other"), pressed)
    }

    @Test fun recyclingCancelsAnAlreadyQueuedClick() {
        touch(MotionEvent.ACTION_DOWN)
        touch(MotionEvent.ACTION_UP)
        binding.update("gallery/other", "other", 0f)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(pressed.isEmpty())
    }

    @Test fun changingSourceInstanceCancelsAnAlreadyQueuedClick() {
        binding.update("gallery/media", "media", 8f, "first-instance")
        touch(MotionEvent.ACTION_DOWN)
        touch(MotionEvent.ACTION_UP)
        binding.update("gallery/media", "media", 8f, "second-instance")
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(pressed.isEmpty())
        tap()
        assertEquals(listOf("media"), pressed)
    }

    @Test fun unregisteringOneSourceDoesNotRemoveItsSibling() {
        val other = FrameLayout(activity.get())
        root.addView(other, FrameLayout.LayoutParams(100, 100))
        val otherImage = ImageView(activity.get()).apply { setImageDrawable(ColorDrawable(Color.RED)) }
        other.addView(otherImage, FrameLayout.LayoutParams(100, 100))
        other.layout(0, 0, 100, 100)
        otherImage.layout(0, 0, 100, 100)
        val otherPressed = mutableListOf<String>()
        val otherBinding = LevixelSourceBinding(other, otherPressed::add)
        otherBinding.update("gallery/media", "media", 4f, "sibling")
        tap()
        other.performClick()
        assertEquals(listOf("media"), pressed)
        assertEquals(listOf("media"), otherPressed)
        root.removeView(source)
        assertSame(otherImage, LevixelSourceViewRegistry.find("gallery/media"))
        other.performClick()
        assertEquals(listOf("media", "media"), otherPressed)
    }

    @Test fun hiddenSourceDoesNotSupplyStaleGeometry() {
        source.visibility = View.GONE
        draw()
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        source.visibility = View.VISIBLE
        draw()
        assertSame(first, LevixelSourceViewRegistry.find("gallery/media"))
    }

    @Test fun detachAndReattachRemoveAndRestoreTheObserverAndBinding() {
        root.removeView(source)
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        assertFalse(source.isClickable)
        source.performClick()
        assertTrue(pressed.isEmpty())
        swap(first, second)
        root.addView(source)
        layout()
        draw()
        tap()
        assertSame(second, LevixelSourceViewRegistry.find("gallery/media"))
        assertEquals(listOf("media"), pressed)
    }

    @Test fun nestedImageReplacementIsObservedWithoutSourceChildEvents() {
        loader.removeView(first)
        draw()
        assertNull(LevixelSourceViewRegistry.find("gallery/media"))
        val replacement = image()
        replacement.layout(0, 0, 100, 100)
        draw()
        assertSame(replacement, LevixelSourceViewRegistry.find("gallery/media"))
        tap()
        assertEquals(listOf("media"), pressed)
    }

    @Test fun cancelledGestureDoesNotOpenAndDoesNotPoisonTheNextTap() {
        touch(MotionEvent.ACTION_DOWN)
        touch(MotionEvent.ACTION_CANCEL)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(pressed.isEmpty())
        tap()
        assertEquals(listOf("media"), pressed)
    }

    @Test fun handledLongPressDoesNotAlsoOpenOnRelease() {
        source.setOnLongClickListener { true }
        touch(MotionEvent.ACTION_DOWN)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(
            (ViewConfiguration.getTapTimeout() + ViewConfiguration.getLongPressTimeout()).toLong()))
        touch(MotionEvent.ACTION_UP)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(pressed.isEmpty())
    }

    @Test fun repeatedCacheSwapsNeverAccumulateClicksOrStaleMappings() {
        repeat(12) { index ->
            val shown = if (index % 2 == 0) second else first
            val hidden = if (index % 2 == 0) first else second
            swap(hidden, shown)
            draw()
            tap()
            assertSame(shown, LevixelSourceViewRegistry.find("gallery/media"))
            assertNull(hidden.transitionName)
        }
        assertEquals(List(12) { "media" }, pressed)
    }

    private fun image() = ImageView(activity.get()).also {
        it.setImageDrawable(ColorDrawable(Color.RED))
        loader.addView(it, FrameLayout.LayoutParams(100, 100))
    }

    private fun layout() {
        root.measure(View.MeasureSpec.makeMeasureSpec(500, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(500, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, 500, 500)
        source.layout(0, 0, 100, 100)
        loader.layout(0, 0, 100, 100)
        first.layout(0, 0, 100, 100)
        second.layout(0, 0, 100, 100)
    }

    private fun swap(old: ImageView, current: ImageView) {
        old.visibility = View.GONE
        old.setImageDrawable(null)
        current.visibility = View.VISIBLE
        current.setImageDrawable(ColorDrawable(Color.BLUE))
    }

    private fun draw() { source.viewTreeObserver.dispatchOnPreDraw() }

    private fun tap() {
        touch(MotionEvent.ACTION_DOWN)
        touch(MotionEvent.ACTION_UP)
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun touch(action: Int) {
        val event = MotionEvent.obtain(0L, 10L, action, 20f, 20f, 0)
        try { source.dispatchTouchEvent(event) } finally { event.recycle() }
    }
}
