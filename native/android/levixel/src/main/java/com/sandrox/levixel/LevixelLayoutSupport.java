package com.sandrox.levixel;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.view.View;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.github.chrisbanes.photoview.PhotoView;

public final class LevixelLayoutSupport {
    private static final int MAX_TRANSITION_BITMAP_SIDE = 2048;

    private LevixelLayoutSupport() {
    }

    @Nullable
    public static LevixelSharedElementState captureImageViewState(@Nullable ImageView imageView) {
        return captureImageViewState(imageView, null);
    }

    @Nullable
    public static LevixelSharedElementState captureImageViewState(@Nullable ImageView imageView, @Nullable RectF clippingFrameInWindow) {
        if (imageView == null) {
            return null;
        }
        Drawable drawable = imageView.getDrawable();
        if (drawable == null || imageView.getWidth() <= 0 || imageView.getHeight() <= 0) {
            return null;
        }

        RectF imageBoundsInWindow = viewBoundsOnScreen(imageView);
        RectF clippingFrame = clippingFrameInWindow != null
                ? new RectF(clippingFrameInWindow)
                : visibleBoundsOnScreen(imageView);
        if (clippingFrame.isEmpty()) {
            clippingFrame = new RectF(imageBoundsInWindow);
        }

        RectF contentFrameInView = resolveDisplayedContentFrame(imageView, drawable);
        if (contentFrameInView == null || contentFrameInView.isEmpty()) {
            return null;
        }

        Drawable transitionDrawable = transitionDrawableForImageView(imageView);
        if (transitionDrawable == null) {
            return null;
        }

        RectF contentFrameInWindow = new RectF(contentFrameInView);
        int[] location = new int[2];
        imageView.getLocationOnScreen(location);
        contentFrameInWindow.offset(location[0], location[1]);

        RectF visibleFrameInWindow = new RectF();
        boolean intersects = visibleFrameInWindow.setIntersect(clippingFrame, contentFrameInWindow);
        if (!intersects || visibleFrameInWindow.isEmpty()) {
            visibleFrameInWindow = new RectF(clippingFrame);
        }

        RectF contentFrameInVisibleBounds = new RectF(
                contentFrameInWindow.left - visibleFrameInWindow.left,
                contentFrameInWindow.top - visibleFrameInWindow.top,
                contentFrameInWindow.right - visibleFrameInWindow.left,
                contentFrameInWindow.bottom - visibleFrameInWindow.top
        );

        return new LevixelSharedElementState(
                transitionDrawable,
                new LevixelSharedElementGeometry(visibleFrameInWindow, contentFrameInVisibleBounds)
        );
    }

    @Nullable
    public static LevixelSharedElementGeometry captureImageViewGeometry(@Nullable ImageView imageView, @Nullable Drawable geometryDrawable) {
        if (imageView == null || imageView.getWidth() <= 0 || imageView.getHeight() <= 0) {
            return null;
        }

        RectF imageBoundsInWindow = viewBoundsOnScreen(imageView);
        RectF clippingFrame = visibleBoundsOnScreen(imageView);
        if (clippingFrame.isEmpty()) {
            clippingFrame = new RectF(imageBoundsInWindow);
        }

        RectF contentFrameInView = null;
        Drawable drawable = geometryDrawable != null ? geometryDrawable : imageView.getDrawable();
        if (drawable != null) {
            contentFrameInView = resolveDisplayedContentFrame(imageView, drawable);
        }
        if (contentFrameInView == null || contentFrameInView.isEmpty()) {
            contentFrameInView = new RectF(0f, 0f, imageView.getWidth(), imageView.getHeight());
        }

        RectF contentFrameInWindow = new RectF(contentFrameInView);
        int[] location = new int[2];
        imageView.getLocationOnScreen(location);
        contentFrameInWindow.offset(location[0], location[1]);

        RectF visibleFrameInWindow = new RectF();
        boolean intersects = visibleFrameInWindow.setIntersect(clippingFrame, contentFrameInWindow);
        if (!intersects || visibleFrameInWindow.isEmpty()) {
            visibleFrameInWindow = new RectF(clippingFrame);
        }

        RectF contentFrameInVisibleBounds = new RectF(
                contentFrameInWindow.left - visibleFrameInWindow.left,
                contentFrameInWindow.top - visibleFrameInWindow.top,
                contentFrameInWindow.right - visibleFrameInWindow.left,
                contentFrameInWindow.bottom - visibleFrameInWindow.top
        );

        return new LevixelSharedElementGeometry(visibleFrameInWindow, contentFrameInVisibleBounds);
    }

    @NonNull
    public static RectF viewBoundsOnScreen(@NonNull View view) {
        int[] location = new int[2];
        view.getLocationOnScreen(location);
        return new RectF(
                location[0],
                location[1],
                location[0] + view.getWidth(),
                location[1] + view.getHeight()
        );
    }

    @NonNull
    public static RectF visibleBoundsOnScreen(@NonNull View view) {
        Rect localVisibleRect = new Rect();
        if (!view.getLocalVisibleRect(localVisibleRect) || localVisibleRect.isEmpty()) {
            return viewBoundsOnScreen(view);
        }

        int[] location = new int[2];
        view.getLocationOnScreen(location);
        return new RectF(
                location[0] + localVisibleRect.left,
                location[1] + localVisibleRect.top,
                location[0] + localVisibleRect.right,
                location[1] + localVisibleRect.bottom
        );
    }

    @Nullable
    public static Drawable cloneDrawable(@Nullable Drawable drawable, @NonNull View view) {
        if (drawable == null) {
            return null;
        }
        Drawable.ConstantState constantState = drawable.getConstantState();
        if (constantState == null) {
            return drawable.mutate();
        }
        return constantState.newDrawable(view.getResources()).mutate();
    }

    @Nullable
    public static Drawable transitionDrawableForImageView(@Nullable ImageView imageView) {
        if (imageView == null) {
            return null;
        }
        Drawable draweeActualDrawable = resolveDraweeActualDrawable(imageView);
        if (draweeActualDrawable != null) {
            Drawable clonedActualDrawable = cloneDrawableFromConstantState(draweeActualDrawable, imageView);
            if (clonedActualDrawable != null) {
                return clonedActualDrawable;
            }
            Drawable bitmapCopy = bitmapDrawableCopy(draweeActualDrawable, imageView);
            if (bitmapCopy != null) {
                return bitmapCopy;
            }
        }
        if (isDraweeRootDrawable(imageView.getDrawable())) {
            return null;
        }
        return cloneDrawable(imageView.getDrawable(), imageView);
    }

    @Nullable
    private static Drawable cloneDrawableFromConstantState(@Nullable Drawable drawable, @NonNull View view) {
        if (drawable == null) {
            return null;
        }
        Drawable.ConstantState constantState = drawable.getConstantState();
        if (constantState == null) {
            return null;
        }
        return constantState.newDrawable(view.getResources()).mutate();
    }

    @Nullable
    private static Drawable bitmapDrawableCopy(@NonNull Drawable drawable, @NonNull View view) {
        int intrinsicWidth = drawable.getIntrinsicWidth();
        int intrinsicHeight = drawable.getIntrinsicHeight();
        if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
            Rect bounds = drawable.getBounds();
            intrinsicWidth = bounds.width();
            intrinsicHeight = bounds.height();
        }
        if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
            return null;
        }

        float scale = Math.min(
                1f,
                MAX_TRANSITION_BITMAP_SIDE / Math.max((float) intrinsicWidth, (float) intrinsicHeight)
        );
        int bitmapWidth = Math.max(1, Math.round(intrinsicWidth * scale));
        int bitmapHeight = Math.max(1, Math.round(intrinsicHeight * scale));

        Bitmap bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        Rect oldBounds = new Rect(drawable.getBounds());
        drawable.setBounds(0, 0, bitmapWidth, bitmapHeight);
        drawable.draw(canvas);
        drawable.setBounds(oldBounds);
        return new BitmapDrawable(view.getResources(), bitmap);
    }

    @NonNull
    public static LevixelSharedElementGeometry defaultGeometryFor(@NonNull Drawable drawable, @NonNull RectF containerBounds) {
        RectF visibleFrame = aspectFitRect(drawable, containerBounds);
        return new LevixelSharedElementGeometry(
                visibleFrame,
                new RectF(0f, 0f, visibleFrame.width(), visibleFrame.height())
        );
    }

    @NonNull
    public static LevixelSharedElementGeometry defaultGeometryForAspectRatio(float width, float height, @NonNull RectF containerBounds) {
        float safeWidth = Math.max(1f, width);
        float safeHeight = Math.max(1f, height);
        float widthScale = containerBounds.width() / safeWidth;
        float heightScale = containerBounds.height() / safeHeight;
        float scale = Math.min(widthScale, heightScale);
        float targetWidth = safeWidth * scale;
        float targetHeight = safeHeight * scale;
        float left = containerBounds.left + (containerBounds.width() - targetWidth) * 0.5f;
        float top = containerBounds.top + (containerBounds.height() - targetHeight) * 0.5f;
        RectF visibleFrame = new RectF(left, top, left + targetWidth, top + targetHeight);
        return new LevixelSharedElementGeometry(
                visibleFrame,
                new RectF(0f, 0f, visibleFrame.width(), visibleFrame.height())
        );
    }

    @NonNull
    public static RectF aspectFitRect(@NonNull Drawable drawable, @NonNull RectF containerBounds) {
        int intrinsicWidth = Math.max(1, drawable.getIntrinsicWidth());
        int intrinsicHeight = Math.max(1, drawable.getIntrinsicHeight());
        float widthScale = containerBounds.width() / intrinsicWidth;
        float heightScale = containerBounds.height() / intrinsicHeight;
        float scale = Math.min(widthScale, heightScale);
        float width = intrinsicWidth * scale;
        float height = intrinsicHeight * scale;
        float left = containerBounds.left + (containerBounds.width() - width) * 0.5f;
        float top = containerBounds.top + (containerBounds.height() - height) * 0.5f;
        return new RectF(left, top, left + width, top + height);
    }

    @Nullable
    private static RectF resolveDisplayedContentFrame(@NonNull ImageView imageView, @NonNull Drawable drawable) {
        RectF viewBounds = new RectF(0f, 0f, imageView.getWidth(), imageView.getHeight());
        if (viewBounds.isEmpty()) {
            return null;
        }

        if (imageView instanceof PhotoView) {
            RectF displayRect = ((PhotoView) imageView).getDisplayRect();
            if (displayRect != null && !displayRect.isEmpty()) {
                return new RectF(displayRect);
            }
        }

        RectF draweeContentFrame = resolveDraweeActualContentFrame(imageView);
        if (draweeContentFrame != null && !draweeContentFrame.isEmpty()) {
            return draweeContentFrame;
        }

        int intrinsicWidth = drawable.getIntrinsicWidth();
        int intrinsicHeight = drawable.getIntrinsicHeight();
        if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
            return new RectF(viewBounds);
        }

        ImageView.ScaleType scaleType = imageView.getScaleType();
        if (scaleType == ImageView.ScaleType.MATRIX) {
            RectF contentFrameInView = new RectF(0f, 0f, intrinsicWidth, intrinsicHeight);
            Matrix imageMatrix = new Matrix(imageView.getImageMatrix());
            imageMatrix.mapRect(contentFrameInView);
            return contentFrameInView;
        }

        if (scaleType == ImageView.ScaleType.FIT_XY) {
            return new RectF(viewBounds);
        }

        float widthScale = viewBounds.width() / intrinsicWidth;
        float heightScale = viewBounds.height() / intrinsicHeight;
        float scale;
        float dx = 0f;
        float dy = 0f;

        switch (scaleType) {
            case CENTER:
                scale = 1f;
                dx = (viewBounds.width() - intrinsicWidth) * 0.5f;
                dy = (viewBounds.height() - intrinsicHeight) * 0.5f;
                break;
            case CENTER_CROP:
                scale = Math.max(widthScale, heightScale);
                dx = (viewBounds.width() - intrinsicWidth * scale) * 0.5f;
                dy = (viewBounds.height() - intrinsicHeight * scale) * 0.5f;
                break;
            case CENTER_INSIDE:
                scale = Math.min(1f, Math.min(widthScale, heightScale));
                dx = (viewBounds.width() - intrinsicWidth * scale) * 0.5f;
                dy = (viewBounds.height() - intrinsicHeight * scale) * 0.5f;
                break;
            case FIT_START:
                scale = Math.min(widthScale, heightScale);
                break;
            case FIT_END:
                scale = Math.min(widthScale, heightScale);
                dx = viewBounds.width() - intrinsicWidth * scale;
                dy = viewBounds.height() - intrinsicHeight * scale;
                break;
            case FIT_CENTER:
            default:
                scale = Math.min(widthScale, heightScale);
                dx = (viewBounds.width() - intrinsicWidth * scale) * 0.5f;
                dy = (viewBounds.height() - intrinsicHeight * scale) * 0.5f;
                break;
        }

        float width = intrinsicWidth * scale;
        float height = intrinsicHeight * scale;
        return new RectF(dx, dy, dx + width, dy + height);
    }

    @Nullable
    private static RectF resolveDraweeActualContentFrame(@NonNull ImageView imageView) {
        try {
            Object hierarchy = imageView.getClass().getMethod("getHierarchy").invoke(imageView);
            if (hierarchy == null) {
                return null;
            }
            RectF bounds = new RectF();
            hierarchy.getClass().getMethod("getActualImageBounds", RectF.class).invoke(hierarchy, bounds);
            if (bounds.width() <= 1f || bounds.height() <= 1f) {
                return null;
            }
            return bounds;
        } catch (Exception ignored) {
            return null;
        }
    }

    @Nullable
    private static Drawable resolveDraweeActualDrawable(@NonNull ImageView imageView) {
        try {
            Object hierarchy = imageView.getClass().getMethod("getHierarchy").invoke(imageView);
            if (hierarchy == null) {
                return null;
            }
            Object hasImage = hierarchy.getClass().getMethod("hasImage").invoke(hierarchy);
            if (!(hasImage instanceof Boolean) || !((Boolean) hasImage)) {
                return null;
            }
            java.lang.reflect.Field actualImageWrapperField = hierarchy.getClass().getDeclaredField("mActualImageWrapper");
            actualImageWrapperField.setAccessible(true);
            Object actualImageWrapper = actualImageWrapperField.get(hierarchy);
            if (actualImageWrapper == null) {
                return null;
            }
            Object actualDrawable = actualImageWrapper.getClass().getMethod("getDrawable").invoke(actualImageWrapper);
            if (actualDrawable instanceof Drawable) {
                return (Drawable) actualDrawable;
            }
        } catch (Exception ignored) {
        }

        return findPositiveIntrinsicLeafDrawable(
                imageView.getDrawable(),
                new java.util.IdentityHashMap<>(),
                0
        );
    }

    @Nullable
    private static Drawable findPositiveIntrinsicLeafDrawable(
            @Nullable Drawable drawable,
            @NonNull java.util.IdentityHashMap<Drawable, Boolean> visited,
            int depth
    ) {
        if (drawable == null || depth > 12 || visited.containsKey(drawable)) {
            return null;
        }
        visited.put(drawable, true);

        if (!isDraweeWrapperDrawable(drawable)
                && drawable.getIntrinsicWidth() > 0
                && drawable.getIntrinsicHeight() > 0) {
            return drawable;
        }

        Drawable current = drawable.getCurrent();
        if (current != null && current != drawable) {
            Drawable found = findPositiveIntrinsicLeafDrawable(current, visited, depth + 1);
            if (found != null) {
                return found;
            }
        }

        try {
            Object count = drawable.getClass().getMethod("getNumberOfLayers").invoke(drawable);
            if (count instanceof Integer) {
                for (int i = ((Integer) count) - 1; i >= 0; i--) {
                    Object layer = drawable.getClass().getMethod("getDrawable", int.class).invoke(drawable, i);
                    if (layer instanceof Drawable) {
                        Drawable found = findPositiveIntrinsicLeafDrawable((Drawable) layer, visited, depth + 1);
                        if (found != null) {
                            return found;
                        }
                    }
                }
            }
        } catch (Exception ignored) {
        }

        return null;
    }

    private static boolean isDraweeRootDrawable(@Nullable Drawable drawable) {
        return drawable != null
                && "com.facebook.drawee.generic.RootDrawable".equals(drawable.getClass().getName());
    }

    private static boolean isDraweeWrapperDrawable(@NonNull Drawable drawable) {
        String className = drawable.getClass().getName();
        return className.startsWith("com.facebook.drawee.");
    }
}
