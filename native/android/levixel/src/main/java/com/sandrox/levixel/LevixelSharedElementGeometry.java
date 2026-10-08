package com.sandrox.levixel;

import android.graphics.RectF;

import androidx.annotation.NonNull;

public final class LevixelSharedElementGeometry {
    private final RectF visibleFrameInWindow;
    private final RectF contentFrameInVisibleBounds;
    private final RectF roundedFrameInVisibleBounds;
    private final float cornerRadius;

    public LevixelSharedElementGeometry(@NonNull RectF visibleFrameInWindow, @NonNull RectF contentFrameInVisibleBounds) {
        this(visibleFrameInWindow, contentFrameInVisibleBounds, 0f);
    }

    public LevixelSharedElementGeometry(
            @NonNull RectF visibleFrameInWindow,
            @NonNull RectF contentFrameInVisibleBounds,
            float cornerRadius
    ) {
        this(visibleFrameInWindow, contentFrameInVisibleBounds,
                new RectF(0f, 0f, visibleFrameInWindow.width(), visibleFrameInWindow.height()), cornerRadius);
    }

    LevixelSharedElementGeometry(
            @NonNull RectF visibleFrameInWindow,
            @NonNull RectF contentFrameInVisibleBounds,
            @NonNull RectF roundedFrameInVisibleBounds,
            float cornerRadius
    ) {
        this.visibleFrameInWindow = new RectF(visibleFrameInWindow);
        this.contentFrameInVisibleBounds = new RectF(contentFrameInVisibleBounds);
        this.roundedFrameInVisibleBounds = new RectF(roundedFrameInVisibleBounds);
        this.cornerRadius = Math.max(0f, cornerRadius);
    }

    @NonNull
    public RectF getVisibleFrameInWindow() {
        return new RectF(visibleFrameInWindow);
    }

    @NonNull
    public RectF getContentFrameInVisibleBounds() {
        return new RectF(contentFrameInVisibleBounds);
    }

    public float getCornerRadius() {
        return cornerRadius;
    }

    @NonNull
    RectF getRoundedFrameInVisibleBounds() {
        return new RectF(roundedFrameInVisibleBounds);
    }
}
