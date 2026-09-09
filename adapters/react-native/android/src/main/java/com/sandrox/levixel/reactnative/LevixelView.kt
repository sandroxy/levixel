package com.sandrox.levixel.reactnative

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import com.sandrox.levixel.LevixelAction
import com.sandrox.levixel.LevixelActionLayout
import com.sandrox.levixel.LevixelViewerEvent
import com.sandrox.levixel.LevixelMediaItem
import com.sandrox.levixel.LevixelSharedElementNames
import com.sandrox.levixel.LevixelSourceViewRegistry
import com.sandrox.levixel.LevixelViewerOverlayView
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.Promise

class LevixelView(context: Context) : ViewGroup(context) {
    var items: List<Map<String, Any?>> = emptyList()
        set(value) {
            field = value
            refreshBinding()
        }
    var initialIndex: Int = 0
        set(value) {
            field = value
            refreshBinding()
        }
    var galleryId: String = ""
        set(value) {
            field = value
            refreshBinding()
        }
    var sourceCornerRadius: Float = 0f
        set(value) {
            require(value.isFinite() && value >= 0f) {
                "Levixel sourceCornerRadius must be a non-negative finite number."
            }
            field = value
            refreshBinding()
        }
    val onSourcePress by EventDispatcher()
    val onViewerEvent by EventDispatcher()

    private var sourceImageView: ImageView? = null
    private var observedSourceImageView: ImageView? = null
    private var sourceImageLayoutListener: View.OnLayoutChangeListener? = null
    private var sourceImageAttachListener: View.OnAttachStateChangeListener? = null
    private var overlayView: LevixelViewerOverlayView? = null
    private var overlayBackCallback: OnBackPressedCallback? = null
    private var activeRequestId: String? = null
    private val closePromises = mutableMapOf<String, MutableList<Promise>>()

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        refreshBinding()
    }

    override fun onViewAdded(child: View) {
        super.onViewAdded(child)
        post { refreshBinding() }
    }

    override fun onViewRemoved(child: View) {
        unregisterSourceImageView()
        super.onViewRemoved(child)
        post { refreshBinding() }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        for (index in 0 until childCount) {
            getChildAt(index).layout(0, 0, width, height)
        }
        refreshBinding()
    }

    override fun onDetachedFromWindow() {
        val overlay = overlayView
        overlayView = null
        activeRequestId = null
        overlayBackCallback?.remove()
        overlayBackCallback = null
        unregisterSourceImageView()
        // The decor may be detaching its children, including this controller.
        // Remove a surviving overlay only after that traversal has completed.
        if (overlay != null) {
            Handler(Looper.getMainLooper()).post { overlay.dismissImmediately() }
        }
        super.onDetachedFromWindow()
    }

    private fun refreshBinding() {
        val mediaItems = buildMediaItems()
        val imageView = findBestImageView(this)
        if (imageView == null || mediaItems.isEmpty()) {
            unregisterSourceImageView()
            return
        }

        val previous = sourceImageView
        if (previous != null && previous !== imageView) {
            clearSourceImageObserver()
            previous.setOnClickListener(null)
            LevixelSourceViewRegistry.unregisterView(previous)
        }

        sourceImageView = imageView
        imageView.setOnClickListener {
            buildMediaItems().getOrNull(initialIndex)?.let { item -> onSourcePress(mapOf("itemId" to item.id)) }
        }
        registerSourceImageViewWhenReady(imageView, mediaItems)
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
            object : LevixelViewerOverlayView.Listener {
                override fun onOverlayDismissed() {
                    backCallback?.remove()
                    // External detach may notify after a replacement has opened.
                    if (activeRequestId == requestId) {
                        overlayView = null
                        activeRequestId = null
                        overlayBackCallback = null
                    }
                    val completed = closePromises.remove(requestId).orEmpty()
                    completed.forEach { it.resolve(null) }
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

    fun close(promise: Promise) {
        val overlay = overlayView
        val requestId = activeRequestId
        if (overlay == null || requestId == null) { promise.resolve(null); return }
        closePromises.getOrPut(requestId) { mutableListOf() }.add(promise)
        overlay.requestClose()
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

    private fun registerSourceImageViewWhenReady(
        imageView: ImageView,
        mediaItems: List<LevixelMediaItem> = buildMediaItems()
    ) {
        if (mediaItems.isEmpty()) {
            if (sourceImageView === imageView) {
                unregisterSourceImageView()
            }
            return
        }
        val safeIndex = initialIndex.coerceIn(0, mediaItems.lastIndex)
        val sourceKey = LevixelSharedElementNames.forItem(scopedGalleryId(), mediaItems[safeIndex])
        if (isSourceImageViewUsable(imageView)) {
            clearSourceImageObserver(imageView)
            LevixelSourceViewRegistry.register(
                sourceKey,
                imageView,
                sourceCornerRadiusInPixels()
            )
        } else {
            observeSourceImageView(imageView)
        }
    }

    private fun observeSourceImageView(imageView: ImageView) {
        if (observedSourceImageView === imageView && sourceImageLayoutListener != null) {
            return
        }

        clearSourceImageObserver()
        observedSourceImageView = imageView
        val layoutListener = View.OnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
            val observed = view as? ImageView ?: return@OnLayoutChangeListener
            if (sourceImageView !== observed) {
                clearSourceImageObserver(observed)
            } else if (isSourceImageViewUsable(observed)) {
                registerSourceImageViewWhenReady(observed)
            }
        }
        val attachListener = object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                val observed = view as? ImageView ?: return
                if (sourceImageView === observed) {
                    registerSourceImageViewWhenReady(observed)
                }
            }

            override fun onViewDetachedFromWindow(view: View) = Unit
        }
        sourceImageLayoutListener = layoutListener
        sourceImageAttachListener = attachListener
        imageView.addOnLayoutChangeListener(layoutListener)
        imageView.addOnAttachStateChangeListener(attachListener)
        imageView.post {
            if (sourceImageView === imageView && isSourceImageViewUsable(imageView)) {
                registerSourceImageViewWhenReady(imageView)
            }
        }
    }

    private fun findBestImageView(root: View): ImageView? {
        var bestImageView: ImageView? = null
        var bestScore = Int.MIN_VALUE

        fun visit(candidate: View) {
            if (candidate is ImageView) {
                val score = sourceImageViewScore(candidate)
                if (score > bestScore) {
                    bestImageView = candidate
                    bestScore = score
                }
            }
            if (candidate is ViewGroup) {
                for (index in 0 until candidate.childCount) {
                    visit(candidate.getChildAt(index))
                }
            }
        }

        visit(root)
        return bestImageView
    }

    private fun sourceImageViewScore(imageView: ImageView): Int {
        var score = 0
        if (imageView.isAttachedToWindow) score += 16
        if (imageView.width > 0 && imageView.height > 0) score += 16
        if (imageView.visibility == View.VISIBLE) score += 16
        if (imageView.isShown) score += 16
        if (imageView.drawable != null) score += 8
        if (imageView === sourceImageView) score += 1
        return score
    }

    private fun isSourceImageViewUsable(imageView: ImageView): Boolean {
        return imageView.isAttachedToWindow && imageView.width > 0 && imageView.height > 0
    }

    private fun clearSourceImageObserver(imageView: ImageView? = null) {
        val observed = observedSourceImageView ?: return
        if (imageView != null && observed !== imageView) {
            return
        }
        sourceImageLayoutListener?.let(observed::removeOnLayoutChangeListener)
        sourceImageAttachListener?.let(observed::removeOnAttachStateChangeListener)
        sourceImageLayoutListener = null
        sourceImageAttachListener = null
        observedSourceImageView = null
    }

    private fun unregisterSourceImageView() {
        clearSourceImageObserver()
        sourceImageView?.let { imageView ->
            imageView.setOnClickListener(null)
            LevixelSourceViewRegistry.unregisterView(imageView)
        }
        sourceImageView = null
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
