package com.sandrox.levixel.reactnative

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import com.sandrox.levixel.LevixelMediaItem
import com.sandrox.levixel.LevixelSharedElementNames
import com.sandrox.levixel.LevixelSourceViewRegistry
import com.sandrox.levixel.LevixelViewerOverlayView
import expo.modules.kotlin.types.Enumerable
import expo.modules.kotlin.viewevent.EventDispatcher

enum class LevixelTheme(val value: String) : Enumerable {
    DARK("dark"),
    LIGHT("light")
}

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
    var theme: LevixelTheme = LevixelTheme.DARK

    val onIndexChange by EventDispatcher()

    private var sourceImageView: ImageView? = null
    private var observedSourceImageView: ImageView? = null
    private var sourceImageLayoutListener: View.OnLayoutChangeListener? = null
    private var sourceImageAttachListener: View.OnAttachStateChangeListener? = null
    private var overlayView: LevixelViewerOverlayView? = null
    private var overlayBackCallback: OnBackPressedCallback? = null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        refreshBinding()
    }

    override fun onViewAdded(child: View) {
        super.onViewAdded(child)
        post { refreshBinding() }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        for (index in 0 until childCount) {
            getChildAt(index).layout(0, 0, width, height)
        }
        refreshBinding()
    }

    override fun onDetachedFromWindow() {
        overlayView?.dismissImmediately()
        overlayView = null
        overlayBackCallback?.remove()
        overlayBackCallback = null
        unregisterSourceImageView()
        super.onDetachedFromWindow()
    }

    private fun refreshBinding() {
        val imageView = findBestImageView(this)
        if (imageView == null) {
            unregisterSourceImageView()
            return
        }

        val previous = sourceImageView
        if (previous != null && previous !== imageView) {
            clearSourceImageObserver()
            if (!isSourceImageViewUsable(previous)) {
                LevixelSourceViewRegistry.unregisterView(previous)
            }
        }

        sourceImageView = imageView
        imageView.setOnClickListener { openViewer(imageView) }
        registerSourceImageViewWhenReady(imageView)
    }

    private fun openViewer(sourceView: ImageView) {
        val mediaItems = buildMediaItems()
        if (mediaItems.isEmpty() || overlayView != null) {
            return
        }

        val safeIndex = initialIndex.coerceIn(0, mediaItems.lastIndex)
        val activity = findActivity(context) ?: return
        val overlayHost = activity.window.decorView as? ViewGroup
            ?: activity.findViewById<ViewGroup>(android.R.id.content)
            ?: return
        LevixelSourceViewRegistry.register(
            LevixelSharedElementNames.forItem(scopedGalleryId(), mediaItems[safeIndex]),
            sourceView
        )

        val overlay = LevixelViewerOverlayView(
            activity,
            mediaItems,
            safeIndex,
            theme == LevixelTheme.LIGHT,
            scopedGalleryId(),
            object : LevixelViewerOverlayView.Listener {
                override fun onOverlayDismissed() {
                    overlayView = null
                    overlayBackCallback?.remove()
                    overlayBackCallback = null
                }

                override fun onOverlayIndexChange(index: Int) {
                    onIndexChange(mapOf("currentIndex" to index))
                }
            }
        )
        overlayView = overlay
        overlayHost.addView(overlay)

        if (activity is ComponentActivity) {
            overlayBackCallback?.remove()
            overlayBackCallback = object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    overlayView?.requestClose()
                }
            }.also { callback ->
                activity.onBackPressedDispatcher.addCallback(callback)
            }
        }
    }

    private fun buildMediaItems(): List<LevixelMediaItem> {
        return items.mapIndexedNotNull { index, value ->
            val type = value["type"] as? String ?: return@mapIndexedNotNull null
            val url = value["url"] as? String ?: return@mapIndexedNotNull null
            val id = (value["id"] as? String)?.takeIf(String::isNotBlank) ?: index.toString()
            if (type.equals("video", ignoreCase = true)) {
                val poster = value["posterUrl"] as? String
                    ?: value["thumbnailUrl"] as? String
                    ?: url
                LevixelMediaItem(id, LevixelMediaItem.MediaType.VIDEO, url, poster)
            } else {
                val thumbnail = value["thumbnailUrl"] as? String ?: url
                LevixelMediaItem(id, LevixelMediaItem.MediaType.IMAGE, url, thumbnail)
            }
        }
    }

    private fun registerSourceImageViewWhenReady(imageView: ImageView) {
        val mediaItems = buildMediaItems()
        if (mediaItems.isEmpty()) {
            return
        }
        val safeIndex = initialIndex.coerceIn(0, mediaItems.lastIndex)
        val sourceKey = LevixelSharedElementNames.forItem(scopedGalleryId(), mediaItems[safeIndex])
        if (isSourceImageViewUsable(imageView)) {
            clearSourceImageObserver(imageView)
            LevixelSourceViewRegistry.register(sourceKey, imageView)
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
        sourceImageView?.let(LevixelSourceViewRegistry::unregisterView)
        sourceImageView = null
    }

    private fun scopedGalleryId(): String? = galleryId.takeIf(String::isNotBlank)

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
