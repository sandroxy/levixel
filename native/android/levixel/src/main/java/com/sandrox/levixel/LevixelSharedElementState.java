package com.sandrox.levixel;

import android.graphics.drawable.Drawable;

import androidx.annotation.NonNull;

public final class LevixelSharedElementState {
    private final Drawable drawable;
    private final LevixelSharedElementGeometry geometry;

    public LevixelSharedElementState(@NonNull Drawable drawable, @NonNull LevixelSharedElementGeometry geometry) {
        this.drawable = drawable;
        this.geometry = geometry;
    }

    @NonNull
    public Drawable getDrawable() {
        return drawable;
    }

    @NonNull
    public LevixelSharedElementGeometry getGeometry() {
        return geometry;
    }
}
