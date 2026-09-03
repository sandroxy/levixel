package com.sandrox.levixel.uniapp.runtime;

import android.graphics.RectF;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.sandrox.levixel.LevixelSourceHint;

import java.util.ArrayList;
import java.util.List;

final class LevixelUniSourceHints {
    private LevixelUniSourceHints() {
    }

    @NonNull
    static List<LevixelSourceHint> map(
            @NonNull List<LevixelUniContract.SourceHint> hints,
            @NonNull RectF viewportFrameInWindow,
            @NonNull RectF visibleViewportFrameInWindow,
            float fallbackRectScale
    ) {
        List<LevixelSourceHint> result = new ArrayList<>(hints.size());
        boolean viewportUsable = viewportFrameInWindow.width() > 1f
                && viewportFrameInWindow.height() > 1f
                && visibleViewportFrameInWindow.width() > 0f
                && visibleViewportFrameInWindow.height() > 0f;
        for (LevixelUniContract.SourceHint hint : hints) {
            result.add(map(
                    hint,
                    viewportFrameInWindow.left,
                    viewportFrameInWindow.top,
                    visibleViewportFrameInWindow,
                    viewportUsable,
                    fallbackRectScale
            ));
        }
        return result;
    }

    @Nullable
    static LevixelSourceHint map(
            @Nullable LevixelUniContract.SourceHint hint,
            float viewportLeftInWindow,
            float viewportTopInWindow,
            @NonNull RectF visibleViewportFrameInWindow,
            boolean viewportUsable,
            float fallbackRectScale
    ) {
        if (hint == null) {
            return null;
        }
        if ("viewport".equals(hint.coordinateSpace) && !viewportUsable) {
            return null;
        }

        float scale = hint.rectScale != null
                ? hint.rectScale.floatValue()
                : fallbackRectScale;
        if (!Float.isFinite(scale) || scale <= 0f) {
            scale = 1f;
        }

        float left = (float) hint.rect.left * scale;
        float top = (float) hint.rect.top * scale;
        if ("viewport".equals(hint.coordinateSpace)) {
            left += viewportLeftInWindow;
            top += viewportTopInWindow;
        }

        float imageWidth = hint.imageSize != null ? (float) hint.imageSize.width : 0f;
        float imageHeight = hint.imageSize != null ? (float) hint.imageSize.height : 0f;
        float width = (float) hint.rect.width * scale;
        float height = (float) hint.rect.height * scale;
        if ("viewport".equals(hint.coordinateSpace)
                && !hasPositiveIntersection(left, top, width, height, visibleViewportFrameInWindow)) {
            return null;
        }
        RectF clippingFrameInWindow = "viewport".equals(hint.coordinateSpace)
                ? visibleViewportFrameInWindow
                : null;
        return new LevixelSourceHint(
                rect(left, top, left + width, top + height),
                clippingFrameInWindow,
                imageWidth,
                imageHeight,
                objectFit(hint.objectFit),
                (float) hint.cornerRadius * scale
        );
    }

    @NonNull
    private static RectF rect(float left, float top, float right, float bottom) {
        RectF rect = new RectF();
        rect.left = left;
        rect.top = top;
        rect.right = right;
        rect.bottom = bottom;
        return rect;
    }

    private static boolean hasPositiveIntersection(
            float left,
            float top,
            float width,
            float height,
            @NonNull RectF clippingFrame
    ) {
        float right = left + width;
        float bottom = top + height;
        return Float.isFinite(left)
                && Float.isFinite(top)
                && Float.isFinite(right)
                && Float.isFinite(bottom)
                && Math.min(right, clippingFrame.right) > Math.max(left, clippingFrame.left)
                && Math.min(bottom, clippingFrame.bottom) > Math.max(top, clippingFrame.top);
    }

    @NonNull
    private static LevixelSourceHint.ObjectFit objectFit(@NonNull String value) {
        if ("contain".equals(value)) {
            return LevixelSourceHint.ObjectFit.CONTAIN;
        }
        if ("fill".equals(value)) {
            return LevixelSourceHint.ObjectFit.FILL;
        }
        return LevixelSourceHint.ObjectFit.COVER;
    }
}
