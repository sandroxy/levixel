package com.sandrox.levixel.reactnative

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import com.sandrox.levixel.LevixelActionLayout
import com.sandrox.levixel.LevixelMediaItem
import com.sandrox.levixel.LevixelViewerOverlayView
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
class LevixelViewTest {
    private lateinit var activity: ActivityController<Activity>
    private lateinit var root: FrameLayout
    private lateinit var sibling: LevixelView
    private lateinit var clicked: LevixelView
    private lateinit var overlay: LevixelViewerOverlayView
    private val initialItems = listOf(item("media"), item("other"))

    @Before fun setUp() {
        activity = Robolectric.buildActivity(Activity::class.java).setup().visible()
        root = FrameLayout(activity.get())
        activity.get().setContentView(root)
        sibling = source("sibling", 0.6f)
        clicked = source("clicked", 0.8f)
        overlay = LevixelViewerOverlayView(activity.get(), initialItems.map {
            LevixelMediaItem(it.getValue("id"), LevixelMediaItem.MediaType.IMAGE,
                it.getValue("url"), it.getValue("url"))
        }, null, 0, false, "gallery", emptyList(), LevixelActionLayout.LIST, false, "clicked", null)
        root.addView(overlay, FrameLayout.LayoutParams(500, 500))
        layout()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertClickedSourceIsSelected()
    }

    @After fun tearDown() {
        if (::overlay.isInitialized) overlay.dismissImmediately()
        activity.pause().stop().destroy()
    }

    @Test fun prependWithItemsFirstKeepsClickedSource() =
        assertStableBatch(listOf(item("older")) + initialItems, indexFirst = false)

    @Test fun prependWithIndexFirstKeepsClickedSource() =
        assertStableBatch(listOf(item("older")) + initialItems, indexFirst = true)

    @Test fun reorderWithItemsFirstKeepsClickedSource() =
        assertStableBatch(initialItems.reversed(), indexFirst = false)

    @Test fun reorderWithIndexFirstKeepsClickedSource() =
        assertStableBatch(initialItems.reversed(), indexFirst = true)

    @Test fun removingTheMediaTakesEffectOnlyWhenPropsAreCommitted() {
        clicked.items = emptyList()
        refreshDuringPropBatch()
        assertClickedSourceIsSelected()
        clicked.commitSourceBinding()
        assertFalse(clicked.isClickable)
        assertEquals(0.8f, clicked.alpha, 0f)
        assertEquals(0f, sibling.alpha, 0f)
        closeAndAssertRestored()
    }

    private fun assertStableBatch(updatedItems: List<Map<String, String>>, indexFirst: Boolean) {
        if (indexFirst) clicked.initialIndex = 1 else clicked.items = updatedItems
        refreshDuringPropBatch()
        assertClickedSourceIsSelected()
        if (indexFirst) clicked.items = updatedItems else clicked.initialIndex = 1
        clicked.commitSourceBinding()
        assertClickedSourceIsSelected()

        // A sibling's later transaction must not take over the session either.
        sibling.items = updatedItems
        sibling.initialIndex = 1
        sibling.sourceCornerRadius = 12f
        sibling.commitSourceBinding()
        assertClickedSourceIsSelected()
        closeAndAssertRestored()
    }

    private fun refreshDuringPropBatch() {
        // Exercise the actual View callbacks, not just a finished binding.update.
        clicked.removeViewAt(0)
        addImage(clicked)
        layout()
        clicked.viewTreeObserver.dispatchOnPreDraw()
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun assertClickedSourceIsSelected() {
        assertTrue(clicked.isAttachedToWindow)
        assertTrue(clicked.isClickable)
        assertEquals(0f, clicked.alpha, 0f)
        assertEquals(0.6f, sibling.alpha, 0f)
    }

    private fun closeAndAssertRestored() {
        overlay.requestClose()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertFalse(overlay.isAttachedToWindow)
        assertEquals(0.8f, clicked.alpha, 0f)
        assertEquals(0.6f, sibling.alpha, 0f)
    }

    private fun source(id: String, opacity: Float) = LevixelView(activity.get()).also {
        it.alpha = opacity
        root.addView(it, FrameLayout.LayoutParams(100, 100))
        addImage(it)
        it.galleryId = "gallery"
        it.sourceId = id
        it.items = initialItems
        it.initialIndex = 0
        it.commitSourceBinding()
    }

    private fun addImage(source: LevixelView) {
        source.addView(ImageView(activity.get()).apply {
            setImageDrawable(BitmapDrawable(resources,
                Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)))
        }, FrameLayout.LayoutParams(100, 100))
    }

    private fun layout() {
        val size = View.MeasureSpec.makeMeasureSpec(500, View.MeasureSpec.EXACTLY)
        root.measure(size, size)
        root.layout(0, 0, 500, 500)
        for (source in listOf(sibling, clicked)) {
            source.forceLayout()
            source.layout(0, 0, 100, 100)
        }
    }

    private fun item(id: String) = mapOf("id" to id, "type" to "image", "url" to "file:///$id.jpg")
}
