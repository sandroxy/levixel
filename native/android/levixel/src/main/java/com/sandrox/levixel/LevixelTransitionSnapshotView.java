package com.sandrox.levixel;

import android.content.Context;
import android.graphics.Outline;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.ImageView;

import androidx.annotation.NonNull;

public final class LevixelTransitionSnapshotView extends FrameLayout {
    private final ImageView imageView;
    private float cornerRadius;

    public LevixelTransitionSnapshotView(@NonNull Context context, @NonNull Drawable drawable) {
        super(context);
        setClipChildren(true);
        setClipToPadding(true);
        imageView = new ImageView(context);
        imageView.setScaleType(ImageView.ScaleType.FIT_XY);
        imageView.setImageDrawable(drawable);
        addView(imageView);
        setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), cornerRadius);
            }
        });
    }

    public void applyGeometry(@NonNull LevixelSharedElementGeometry geometry) {
        RectF visibleFrame = geometry.getVisibleFrameInWindow();
        FrameLayout.LayoutParams layoutParams = (FrameLayout.LayoutParams) getLayoutParams();
        if (layoutParams == null) {
            layoutParams = new FrameLayout.LayoutParams(
                    Math.max(1, Math.round(visibleFrame.width())),
                    Math.max(1, Math.round(visibleFrame.height()))
            );
        }
        layoutParams.width = Math.max(1, Math.round(visibleFrame.width()));
        layoutParams.height = Math.max(1, Math.round(visibleFrame.height()));
        layoutParams.leftMargin = 0;
        layoutParams.topMargin = 0;
        layoutParams.gravity = Gravity.TOP | Gravity.START;
        setLayoutParams(layoutParams);
        setX(visibleFrame.left);
        setY(visibleFrame.top);

        RectF contentFrame = geometry.getContentFrameInVisibleBounds();
        FrameLayout.LayoutParams imageLayoutParams = (FrameLayout.LayoutParams) imageView.getLayoutParams();
        if (imageLayoutParams == null) {
            imageLayoutParams = new FrameLayout.LayoutParams(
                    Math.max(1, Math.round(contentFrame.width())),
                    Math.max(1, Math.round(contentFrame.height()))
            );
        }
        imageLayoutParams.width = Math.max(1, Math.round(contentFrame.width()));
        imageLayoutParams.height = Math.max(1, Math.round(contentFrame.height()));
        imageLayoutParams.leftMargin = 0;
        imageLayoutParams.topMargin = 0;
        imageLayoutParams.gravity = Gravity.TOP | Gravity.START;
        imageView.setLayoutParams(imageLayoutParams);
        imageView.setX(contentFrame.left);
        imageView.setY(contentFrame.top);

        cornerRadius = Math.max(0f, geometry.getCornerRadius());
        setClipToOutline(cornerRadius > 0.01f);
        if (cornerRadius > 0.01f) {
            invalidateOutline();
        }
    }
}
