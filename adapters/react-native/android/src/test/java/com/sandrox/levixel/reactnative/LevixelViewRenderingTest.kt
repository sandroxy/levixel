package com.sandrox.levixel.reactnative

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.widget.ImageView
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlags
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.facebook.react.uimanager.DisplayMetricsHolder
import com.facebook.react.uimanager.LengthPercentage
import com.facebook.react.uimanager.LengthPercentageType
import com.facebook.react.uimanager.style.BorderRadiusProp
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "mdpi", shadows = [LevixelViewRenderingTest.ReactFlags::class])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LevixelViewRenderingTest {
    private lateinit var source: LevixelView

    @Before fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        DisplayMetricsHolder.initDisplayMetrics(context)
        source = LevixelView(context)
        replaceImage(Color.RED)
    }

    @Test fun uniformRadiusClipsTheImageWithoutAnOuterWrapper() {
        setRadius(24f)
        assertRounded(render(), Color.RED)
    }

    @Test fun radiusUpdatesAndRemovalChangeTheRenderedCorners() {
        setRadius(24f)
        assertEquals(Color.TRANSPARENT, render().getPixel(5, 5))
        setRadius(8f)
        assertEquals(Color.RED, render().getPixel(5, 5))
        setRadius(24f)
        assertEquals(Color.TRANSPARENT, render().getPixel(5, 5))
        setRadius(0f)
        assertEquals(Color.RED, render().getPixel(0, 0))
    }

    @Test fun resizingAndReplacingTheImagePreserveClipping() {
        setRadius(16f)
        assertRounded(render(), Color.RED)
        assertRounded(render(60, 40), Color.RED)
        replaceImage(Color.BLUE)
        assertRounded(render(60, 40), Color.BLUE)
        assertRounded(render(120, 80), Color.BLUE)
    }

    private fun setRadius(radius: Float) {
        // Apply the same RN style as Expo's borderRadius prop, independently
        // of the radius metadata sent to the shared-element transition.
        source.sourceCornerRadius = radius
        BackgroundStyleApplicator.setBorderRadius(source, BorderRadiusProp.BORDER_RADIUS,
            LengthPercentage(radius, LengthPercentageType.POINT))
    }

    private fun replaceImage(color: Int) {
        source.removeAllViews()
        source.addView(ImageView(source.context).apply {
            setImageDrawable(ColorDrawable(color))
        })
    }

    private fun render(width: Int = 100, height: Int = 80): Bitmap {
        source.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        source.layout(0, 0, width, height)
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
            source.draw(Canvas(it))
        }
    }

    private fun assertRounded(bitmap: Bitmap, color: Int) {
        assertEquals(Color.TRANSPARENT, bitmap.getPixel(0, 0))
        assertEquals(Color.TRANSPARENT, bitmap.getPixel(bitmap.width - 1, 0))
        assertEquals(Color.TRANSPARENT, bitmap.getPixel(0, bitmap.height - 1))
        assertEquals(Color.TRANSPARENT, bitmap.getPixel(bitmap.width - 1, bitmap.height - 1))
        assertEquals(color, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
    }

    // Use RN's current drawable implementation without loading its device JNI
    // feature-flag library into this host JVM. The drawing code stays real.
    @Implements(ReactNativeFeatureFlags::class, isInAndroidSdk = false)
    class ReactFlags {
        companion object {
            @JvmStatic @Implementation
            fun enableNewBackgroundAndBorderDrawables(): Boolean = true
        }
    }
}
