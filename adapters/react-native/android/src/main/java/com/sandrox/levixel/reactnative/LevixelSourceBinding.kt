package com.sandrox.levixel.reactnative

import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.ImageView
import com.sandrox.levixel.LevixelSourceViewRegistry

/** Keeps a Source's tap target stable while image loaders replace its rendered child. */
internal class LevixelSourceBinding(
    private val source: ViewGroup,
    private val onPress: (String) -> Unit
) : View.OnAttachStateChangeListener, ViewTreeObserver.OnPreDrawListener {
    private var sourceKey: String? = null
    private var itemId: String? = null
    private var cornerRadius = 0f
    private var registeredImage: ImageView? = null
    private var registeredKey: String? = null
    private var registeredCornerRadius = 0f
    private var observer: ViewTreeObserver? = null

    init {
        // Do not intercept touches: the normal View click machinery still lets
        // scrolling and ancestor gestures cancel a tap. No listener is installed
        // on a loader-owned ImageView that can become hidden or be recycled.
        source.setOnClickListener {
            if (source.isAttachedToWindow) {
                refresh()
                itemId?.let(onPress)
            }
        }
        source.isClickable = false
        source.addOnAttachStateChangeListener(this)
    }

    fun update(key: String?, id: String?, radius: Float) {
        if (key != sourceKey || id != itemId) {
            // A recycled cell must not deliver the previous item's in-flight tap.
            source.cancelPendingInputEvents()
            source.isPressed = false
        }
        sourceKey = key
        itemId = id
        cornerRadius = radius
        refresh()
    }

    fun refresh() {
        val key = sourceKey
        if (!source.isAttachedToWindow || key == null || itemId == null) {
            source.isClickable = false
            stopObserving()
            clearRegistration()
            return
        }
        source.isClickable = true
        if (observer !== source.viewTreeObserver) {
            stopObserving()
            observer = source.viewTreeObserver.also { it.addOnPreDrawListener(this) }
        }
        val image = findDisplayedImage()
        if (image !== registeredImage || key != registeredKey || cornerRadius != registeredCornerRadius) {
            // Update the stable owner atomically, even between drawable loads.
            LevixelSourceViewRegistry.registerSource(key, image, cornerRadius, source)
            registeredImage = image
            registeredKey = key
            registeredCornerRadius = cornerRadius
        }
    }

    override fun onPreDraw(): Boolean {
        // Observe existing draws, not a timer or a self-scheduled frame loop.
        // Image completion/visibility changes need not lay out the RN parent.
        refresh()
        return true
    }

    override fun onViewAttachedToWindow(view: View) = refresh()

    override fun onViewDetachedFromWindow(view: View) {
        stopObserving()
        clearRegistration()
        source.isClickable = false
    }

    private fun stopObserving() {
        observer?.takeIf { it.isAlive }?.removeOnPreDrawListener(this)
        observer = null
    }

    private fun clearRegistration() {
        if (registeredKey != null) LevixelSourceViewRegistry.unregisterSource(source)
        registeredImage = null
        registeredKey = null
    }

    private fun findDisplayedImage(): ImageView? {
        if (!source.isShown) return null
        var best: ImageView? = null
        var bestAlpha = -1f
        var bestArea = -1L
        fun visit(view: View, parentAlpha: Float) {
            if (view.visibility != View.VISIBLE) return
            val alpha = parentAlpha * view.alpha
            if (alpha <= 0f) return
            if (view is ImageView && view.isAttachedToWindow && view.width > 0 && view.height > 0 && view.drawable != null) {
                val area = view.width.toLong() * view.height
                if (alpha > bestAlpha || (alpha == bestAlpha && area > bestArea)) {
                    best = view
                    bestAlpha = alpha
                    bestArea = area
                }
            }
            if (view is ViewGroup) {
                // Equal candidates prefer the frontmost child. During a fade,
                // prefer the image contributing most to the current thumbnail.
                for (index in view.childCount - 1 downTo 0) visit(view.getChildAt(index), alpha)
            }
        }
        // The viewer deliberately hides Source itself; that alpha must not
        // make its actual image disappear from source resolution.
        for (index in source.childCount - 1 downTo 0) visit(source.getChildAt(index), 1f)
        return best
    }
}
