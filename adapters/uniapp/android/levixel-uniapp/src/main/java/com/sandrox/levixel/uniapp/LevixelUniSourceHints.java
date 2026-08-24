package com.sandrox.levixel.uniapp;

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
            @NonNull RectF viewportBoundsInWindow,
            float fallbackRectScale
    ) {
        List<LevixelSourceHint> result = new ArrayList<>(hints.size());
        boolean viewportUsable = viewportBoundsInWindow.width() > 1f
                && viewportBoundsInWindow.height() > 1f;
        for (LevixelUniContract.SourceHint hint : hints) {
            result.add(map(
                    hint,
                    viewportBoundsInWindow.left,
                    viewportBoundsInWindow.top,
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
        return new LevixelSourceHint(
                left,
                top,
                (float) hint.rect.width * scale,
                (float) hint.rect.height * scale,
                imageWidth,
                imageHeight,
                objectFit(hint.objectFit),
                (float) hint.cornerRadius * scale
        );
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
