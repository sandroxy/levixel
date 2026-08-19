package com.sandrox.levixel;

import android.graphics.RectF;

import androidx.annotation.NonNull;

public final class LevixelSharedElementGeometry {
    private final RectF visibleFrameInWindow;
    private final RectF contentFrameInVisibleBounds;

    public LevixelSharedElementGeometry(@NonNull RectF visibleFrameInWindow, @NonNull RectF contentFrameInVisibleBounds) {
        this.visibleFrameInWindow = new RectF(visibleFrameInWindow);
        this.contentFrameInVisibleBounds = new RectF(contentFrameInVisibleBounds);
    }

    @NonNull
    public RectF getVisibleFrameInWindow() {
        return new RectF(visibleFrameInWindow);
    }

    @NonNull
    public RectF getContentFrameInVisibleBounds() {
        return new RectF(contentFrameInVisibleBounds);
    }
}
