package com.sandrox.levixel;

import android.graphics.RectF;
import android.graphics.drawable.Drawable;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

/** Immutable source geometry for callers whose source image is not an Android View. */
public final class LevixelSourceHint {
    public enum ObjectFit {
        COVER,
        CONTAIN,
        FILL
    }

    private final float sourceLeftInWindow;
    private final float sourceTopInWindow;
    private final float sourceWidth;
    private final float sourceHeight;
    private final float imageWidth;
    private final float imageHeight;
    @NonNull
    private final ObjectFit objectFit;
    private final float cornerRadius;
    private final boolean hasClippingFrame;
    private final float clippingLeftInWindow;
    private final float clippingTopInWindow;
    private final float clippingRightInWindow;
    private final float clippingBottomInWindow;

    public LevixelSourceHint(
            @NonNull RectF sourceFrameInWindow,
            float imageWidth,
            float imageHeight,
            @NonNull ObjectFit objectFit,
            float cornerRadius
    ) {
        this(
                sourceFrameInWindow,
                null,
                imageWidth,
                imageHeight,
                objectFit,
                cornerRadius
        );
    }

    /**
     * Creates a source hint whose visible geometry is additionally clipped to a host viewport.
     * The source frame remains unmodified so aspect-fill and aspect-fit crop offsets stay exact.
     */
    public LevixelSourceHint(
            @NonNull RectF sourceFrameInWindow,
            @Nullable RectF clippingFrameInWindow,
            float imageWidth,
            float imageHeight,
            @NonNull ObjectFit objectFit,
            float cornerRadius
    ) {
        this(
                sourceFrameInWindow.left,
                sourceFrameInWindow.top,
                sourceFrameInWindow.right - sourceFrameInWindow.left,
                sourceFrameInWindow.bottom - sourceFrameInWindow.top,
                imageWidth,
                imageHeight,
                objectFit,
                cornerRadius,
                clippingFrameInWindow
        );
    }

    public LevixelSourceHint(
            float sourceLeftInWindow,
            float sourceTopInWindow,
            float sourceWidth,
            float sourceHeight,
            float imageWidth,
            float imageHeight,
            @NonNull ObjectFit objectFit,
            float cornerRadius
    ) {
        this(
                sourceLeftInWindow,
                sourceTopInWindow,
                sourceWidth,
                sourceHeight,
                imageWidth,
                imageHeight,
                objectFit,
                cornerRadius,
                null
        );
    }

    private LevixelSourceHint(
            float sourceLeftInWindow,
            float sourceTopInWindow,
            float sourceWidth,
            float sourceHeight,
            float imageWidth,
            float imageHeight,
            @NonNull ObjectFit objectFit,
            float cornerRadius,
            @Nullable RectF clippingFrameInWindow
    ) {
        this.sourceLeftInWindow = sourceLeftInWindow;
        this.sourceTopInWindow = sourceTopInWindow;
        this.sourceWidth = sourceWidth;
        this.sourceHeight = sourceHeight;
        this.imageWidth = imageWidth;
        this.imageHeight = imageHeight;
        this.objectFit = objectFit;
        this.cornerRadius = Math.max(0f, cornerRadius);
        hasClippingFrame = clippingFrameInWindow != null;
        clippingLeftInWindow = hasClippingFrame ? clippingFrameInWindow.left : 0f;
        clippingTopInWindow = hasClippingFrame ? clippingFrameInWindow.top : 0f;
        clippingRightInWindow = hasClippingFrame ? clippingFrameInWindow.right : 0f;
        clippingBottomInWindow = hasClippingFrame ? clippingFrameInWindow.bottom : 0f;
    }

    public float getSourceLeftInWindow() {
        return sourceLeftInWindow;
    }

    public float getSourceTopInWindow() {
        return sourceTopInWindow;
    }

    public float getSourceWidth() {
        return sourceWidth;
    }

    public float getSourceHeight() {
        return sourceHeight;
    }

    @Nullable
    public LevixelSharedElementGeometry resolveGeometry(
            @NonNull RectF overlayBoundsInWindow,
            @Nullable Drawable fallbackDrawable
    ) {
        float fallbackWidth = fallbackDrawable != null ? fallbackDrawable.getIntrinsicWidth() : 0f;
        float fallbackHeight = fallbackDrawable != null ? fallbackDrawable.getIntrinsicHeight() : 0f;
        ResolvedGeometry resolved = resolve(
                overlayBoundsInWindow.left,
                overlayBoundsInWindow.top,
                overlayBoundsInWindow.right,
                overlayBoundsInWindow.bottom,
                fallbackWidth,
                fallbackHeight
        );
        if (resolved == null) {
            return null;
        }
        return new LevixelSharedElementGeometry(
                new RectF(
                        resolved.visibleLeft,
                        resolved.visibleTop,
                        resolved.visibleRight,
                        resolved.visibleBottom
                ),
                new RectF(
                        resolved.contentLeft,
                        resolved.contentTop,
                        resolved.contentRight,
                        resolved.contentBottom
                ),
                resolved.cornerRadius
        );
    }

    @Nullable
    ResolvedGeometry resolve(
            float overlayLeft,
            float overlayTop,
            float overlayRight,
            float overlayBottom,
            float fallbackImageWidth,
            float fallbackImageHeight
    ) {
        float sourceRight = sourceLeftInWindow + sourceWidth;
        float sourceBottom = sourceTopInWindow + sourceHeight;
        if (!hasUsableSourceSize(sourceLeftInWindow, sourceTopInWindow, sourceRight, sourceBottom)) {
            return null;
        }

        float clippedLeft = Math.max(sourceLeftInWindow, overlayLeft);
        float clippedTop = Math.max(sourceTopInWindow, overlayTop);
        float clippedRight = Math.min(sourceRight, overlayRight);
        float clippedBottom = Math.min(sourceBottom, overlayBottom);
        if (hasClippingFrame) {
            clippedLeft = Math.max(clippedLeft, clippingLeftInWindow);
            clippedTop = Math.max(clippedTop, clippingTopInWindow);
            clippedRight = Math.min(clippedRight, clippingRightInWindow);
            clippedBottom = Math.min(clippedBottom, clippingBottomInWindow);
        }
        if (!hasPositiveArea(clippedLeft, clippedTop, clippedRight, clippedBottom)) {
            return null;
        }

        float resolvedImageWidth = imageWidth > 0f ? imageWidth : fallbackImageWidth;
        float resolvedImageHeight = imageHeight > 0f ? imageHeight : fallbackImageHeight;
        if (resolvedImageWidth <= 0f || resolvedImageHeight <= 0f) {
            resolvedImageWidth = sourceWidth;
            resolvedImageHeight = sourceHeight;
        }

        float contentLeft = sourceLeftInWindow;
        float contentTop = sourceTopInWindow;
        float contentRight = sourceRight;
        float contentBottom = sourceBottom;
        if (objectFit != ObjectFit.FILL) {
            float widthScale = sourceWidth / Math.max(1f, resolvedImageWidth);
            float heightScale = sourceHeight / Math.max(1f, resolvedImageHeight);
            float scale = objectFit == ObjectFit.COVER
                    ? Math.max(widthScale, heightScale)
                    : Math.min(widthScale, heightScale);
            float contentWidth = resolvedImageWidth * scale;
            float contentHeight = resolvedImageHeight * scale;
            contentLeft = sourceLeftInWindow + (sourceWidth - contentWidth) * 0.5f;
            contentTop = sourceTopInWindow + (sourceHeight - contentHeight) * 0.5f;
            contentRight = contentLeft + contentWidth;
            contentBottom = contentTop + contentHeight;
        }

        float visibleLeft = Math.max(clippedLeft, contentLeft);
        float visibleTop = Math.max(clippedTop, contentTop);
        float visibleRight = Math.min(clippedRight, contentRight);
        float visibleBottom = Math.min(clippedBottom, contentBottom);
        if (!hasPositiveArea(visibleLeft, visibleTop, visibleRight, visibleBottom)) {
            return null;
        }

        boolean fullContainerVisible = approximatelyEqual(visibleLeft, sourceLeftInWindow)
                && approximatelyEqual(visibleTop, sourceTopInWindow)
                && approximatelyEqual(visibleRight, sourceRight)
                && approximatelyEqual(visibleBottom, sourceBottom);
        return new ResolvedGeometry(
                visibleLeft,
                visibleTop,
                visibleRight,
                visibleBottom,
                contentLeft - visibleLeft,
                contentTop - visibleTop,
                contentRight - visibleLeft,
                contentBottom - visibleTop,
                fullContainerVisible ? Math.min(cornerRadius, Math.min(sourceWidth, sourceHeight) * 0.5f) : 0f
        );
    }

    private static boolean hasUsableSourceSize(float left, float top, float right, float bottom) {
        return Float.isFinite(left)
                && Float.isFinite(top)
                && Float.isFinite(right)
                && Float.isFinite(bottom)
                && right - left > 1f
                && bottom - top > 1f;
    }

    private static boolean hasPositiveArea(float left, float top, float right, float bottom) {
        return Float.isFinite(left)
                && Float.isFinite(top)
                && Float.isFinite(right)
                && Float.isFinite(bottom)
                && right > left
                && bottom > top;
    }

    private static boolean approximatelyEqual(float first, float second) {
        return Math.abs(first - second) <= 0.5f;
    }

    static final class ResolvedGeometry {
        final float visibleLeft;
        final float visibleTop;
        final float visibleRight;
        final float visibleBottom;
        final float contentLeft;
        final float contentTop;
        final float contentRight;
        final float contentBottom;
        final float cornerRadius;

        ResolvedGeometry(
                float visibleLeft,
                float visibleTop,
                float visibleRight,
                float visibleBottom,
                float contentLeft,
                float contentTop,
                float contentRight,
                float contentBottom,
                float cornerRadius
        ) {
            this.visibleLeft = visibleLeft;
            this.visibleTop = visibleTop;
            this.visibleRight = visibleRight;
            this.visibleBottom = visibleBottom;
            this.contentLeft = contentLeft;
            this.contentTop = contentTop;
            this.contentRight = contentRight;
            this.contentBottom = contentBottom;
            this.cornerRadius = cornerRadius;
        }
    }
}
