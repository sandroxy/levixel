package com.sandrox.levixel.reactnative

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.sandrox.levixel.LevixelAction
import com.sandrox.levixel.LevixelActionLayout
import com.sandrox.levixel.LevixelViewerEvent
import com.sandrox.levixel.LevixelMediaItem
import com.sandrox.levixel.LevixelSharedElementNames
import com.sandrox.levixel.LevixelViewerOverlayView
import expo.modules.kotlin.viewevent.EventDispatcher
import kotlinx.coroutines.CompletableDeferred

class LevixelView(context: Context) : ViewGroup(context) {
    var items: List<Map<String, Any?>> = emptyList()
    var initialIndex: Int = 0
    var galleryId: String = ""
    var sourceId: String = ""
    var isController: Boolean = false
    var sourceCornerRadius: Float = 0f
        set(value) {
            require(value.isFinite() && value >= 0f) {
                "Levixel sourceCornerRadius must be a non-negative finite number."
            }
            field = value
        }
    val onSourcePress by EventDispatcher()
    val onViewerEvent by EventDispatcher()
    val onControllerReady by EventDispatcher()

    private var controllerReady = false
    private var boundSourceId = ""
    private val sourceBinding = LevixelSourceBinding(this) { itemId ->
        onSourcePress(mapOf("itemId" to itemId, "sourceId" to boundSourceId))
    }
    private var overlayView: LevixelViewerOverlayView? = null
    private var overlayBackCallback: OnBackPressedCallback? = null
    private var activeRequestId: String? = null
    private val closeCompletions = mutableMapOf<String, CompletableDeferred<Unit>>()

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        sourceBinding.refresh()
        notifyControllerReady()
    }

    override fun onViewAdded(child: View) {
        super.onViewAdded(child)
        post { sourceBinding.refresh() }
    }

    override fun onViewRemoved(child: View) {
        super.onViewRemoved(child)
        sourceBinding.refresh()
        post { sourceBinding.refresh() }
    }

    override fun dispatchDraw(canvas: Canvas) {
        // RN applies borderRadius to the background; clip image children too,
        // using the same drawing path as ExpoView and ReactViewGroup.
        if (clipToPadding) BackgroundStyleApplicator.clipToPaddingBox(this, canvas)
        super.dispatchDraw(canvas)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        for (index in 0 until childCount) {
            getChildAt(index).layout(0, 0, width, height)
        }
        sourceBinding.refresh()
    }

    override fun onDetachedFromWindow() {
        controllerReady = false
        val overlay = overlayView
        overlayView = null
        activeRequestId = null
        overlayBackCallback?.remove()
        overlayBackCallback = null
        // The decor may be detaching its children, including this controller.
        // Remove a surviving overlay only after that traversal has completed.
        if (overlay != null) {
            Handler(Looper.getMainLooper()).post { overlay.dismissImmediately() }
        }
        super.onDetachedFromWindow()
    }

    // Expo calls this after every prop in the transaction has been applied.
    // Layout/image callbacks refresh this committed binding, never partial props.
    fun commitSourceBinding() {
        val item = buildMediaItems().getOrNull(initialIndex)
        boundSourceId = sourceId
        sourceBinding.update(
            item?.let { LevixelSharedElementNames.forItem(scopedGalleryId(), it) },
            item?.id,
            sourceCornerRadiusInPixels(),
            boundSourceId.takeIf(String::isNotBlank)
        )
        notifyControllerReady()
    }

    private fun notifyControllerReady() {
        if (isController && isAttachedToWindow && !controllerReady) {
            controllerReady = true
            onControllerReady(emptyMap())
        }
    }

    @Suppress("UNCHECKED_CAST")
    fun open(options: Map<String, Any?>) {
        check(isAttachedToWindow) { "Levixel is not mounted." }
        val sourceItems = options["items"] as? List<Map<String, Any?>>
            ?: throw IllegalArgumentException("Levixel items are required.")
        val requestId = options["requestId"] as? String ?: error("Levixel requestId is required.")
        val targetGalleryId = options["galleryId"] as? String ?: error("Levixel galleryId is required.")
        val index = (options["index"] as? Number)?.toInt() ?: 0
        val lightTheme = options["theme"] == "light"
        require(!options.containsKey("actionLayout") || options["actionLayout"] is String) { "Levixel actionLayout must be list or grid." }
        val actionLayout = LevixelActionLayout.fromValue(options["actionLayout"] as? String ?: "list")
        require(!options.containsKey("actionListIcons") || options["actionListIcons"] is Boolean) { "Levixel actionListIcons must be boolean." }
        val actionListIcons = options["actionListIcons"] as? Boolean ?: false
        val actions = (options["actions"] as? List<Map<String, Any?>> ?: emptyList()).map { value ->
            LevixelAction(
                value["id"] as String, value["label"] as String,
                value["icon"] as? String, value["group"] as? String,
                value["disabled"] == true, value["destructive"] == true, null
            )
        }
        val mediaItems = buildMediaItems(sourceItems)
        require(mediaItems.isNotEmpty() && index in mediaItems.indices) { "Levixel items or index are invalid." }
        LevixelAction.snapshot(actions, actionLayout)
        val activity = findActivity(context) ?: error("Levixel requires an Activity.")
        val overlayHost = activity.window.decorView as? ViewGroup
            ?: error("Levixel requires an attached window.")
        overlayView?.dismissImmediately()
        var backCallback: OnBackPressedCallback? = null
        val overlay = LevixelViewerOverlayView(
            activity, mediaItems, null, index, lightTheme, targetGalleryId, actions, actionLayout, actionListIcons,
            options["sourceId"] as? String,
            object : LevixelViewerOverlayView.Listener {
                override fun onOverlayDismissed() {
                    backCallback?.remove()
                    // External detach may notify after a replacement has opened.
                    if (activeRequestId == requestId) {
                        overlayView = null
                        activeRequestId = null
                        overlayBackCallback = null
                    }
                    closeCompletions.remove(requestId)?.complete(Unit)
                }
                override fun onOverlayIndexChange(index: Int) = Unit
                override fun onViewerEvent(event: LevixelViewerEvent) {
                    onViewerEvent(event.toMap() + mapOf("requestId" to requestId))
                }
            }
        )
        overlayView = overlay
        activeRequestId = requestId
        overlayHost.addView(overlay)
        if (activity is ComponentActivity) {
            backCallback = object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() { overlay.handleBack() }
            }.also { activity.onBackPressedDispatcher.addCallback(it) }
            overlayBackCallback = backCallback
        }
    }

    suspend fun close() {
        val overlay = overlayView
        val requestId = activeRequestId
        if (overlay == null || requestId == null) return
        val completion = closeCompletions.getOrPut(requestId) { CompletableDeferred() }
        overlay.requestClose()
        // Concurrent callers share this session's completion, including detach
        // or replacement. Returning the JS promise must wait for actual dismissal.
        completion.await()
    }
    fun retry(): Boolean = overlayView?.retry() ?: false

    private fun buildMediaItems(values: List<Map<String, Any?>> = items): List<LevixelMediaItem> {
        val mediaItems = ArrayList<LevixelMediaItem>(values.size)
        val itemIds = HashSet<String>(values.size)
        for (value in values) {
            val type = value["type"] as? String ?: return emptyList()
            val url = (value["url"] as? String)?.takeIf(String::isNotBlank)
                ?: return emptyList()
            val id = (value["id"] as? String)?.takeIf(String::isNotBlank)
                ?: return emptyList()
            if (!itemIds.add(id)) {
                return emptyList()
            }

            val mediaItem = when (type) {
                "video" -> {
                    val poster = value["posterUrl"] as? String
                        ?: value["thumbnailUrl"] as? String
                        ?: url
                    LevixelMediaItem(id, LevixelMediaItem.MediaType.VIDEO, url, poster)
                }
                "image" -> {
                    val thumbnail = value["thumbnailUrl"] as? String ?: url
                    LevixelMediaItem(id, LevixelMediaItem.MediaType.IMAGE, url, thumbnail)
                }
                else -> return emptyList()
            }
            mediaItems.add(mediaItem)
        }
        return mediaItems
    }

    private fun scopedGalleryId(): String? = galleryId.takeIf(String::isNotBlank)

    private fun sourceCornerRadiusInPixels(): Float =
        sourceCornerRadius * resources.displayMetrics.density

    private fun findActivity(sourceContext: Context): Activity? {
        var current = sourceContext
        while (current is ContextWrapper) {
            if (current is Activity) {
                return current
            }
            current = current.baseContext
        }
        return null
    }
}
