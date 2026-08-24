package com.sandrox.levixel;

import android.animation.ObjectAnimator;
import android.content.Context;
import android.graphics.Color;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.ProgressBar;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.bumptech.glide.Glide;
import com.bumptech.glide.load.engine.GlideException;
import com.bumptech.glide.request.RequestListener;
import com.bumptech.glide.request.target.Target;
import com.github.chrisbanes.photoview.PhotoView;

public final class LevixelViewerPageView extends FrameLayout {
    public interface Listener {
        void onDismissRequested(@NonNull LevixelViewerPageView pageView);

        void onVideoCloseRequested(@NonNull LevixelViewerPageView pageView);
    }

    private final FrameLayout mediaContainer;
    private final PhotoView photoView;
    private final ImageView previewImageView;
    private final LevixelVideoPlayerView videoPlayerView;
    private final FrameLayout loadingContainer;
    private final ObjectAnimator loadingPulseAnimator;
    @Nullable
    private LevixelMediaItem item;
    @Nullable
    private Listener listener;
    private boolean active;
    private boolean allowParentInterceptOnImageEdge;
    private boolean fullImageReady;
    private int bindGeneration;

    public LevixelViewerPageView(@NonNull Context context) {
        super(context);
        setLayoutParams(new LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        setBackgroundColor(Color.TRANSPARENT);

        mediaContainer = new FrameLayout(context);
        mediaContainer.setLayoutParams(new LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        mediaContainer.setBackgroundColor(Color.TRANSPARENT);
        addView(mediaContainer);

        photoView = new PhotoView(context);
        photoView.setLayoutParams(new LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        photoView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        photoView.setBackgroundColor(Color.TRANSPARENT);
        photoView.setVisibility(GONE);
        photoView.setOnViewTapListener((view, x, y) -> {
            if (listener != null) {
                listener.onDismissRequested(this);
            }
        });
        mediaContainer.addView(photoView);

        previewImageView = new ImageView(context);
        previewImageView.setLayoutParams(new LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        previewImageView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        previewImageView.setBackgroundColor(Color.TRANSPARENT);
        previewImageView.setVisibility(GONE);
        mediaContainer.addView(previewImageView);

        videoPlayerView = new LevixelVideoPlayerView(context);
        videoPlayerView.setVisibility(GONE);
        videoPlayerView.setListener(() -> {
            if (listener != null) {
                listener.onVideoCloseRequested(this);
            }
        });
        videoPlayerView.setOnContentReadyListener(() -> setLoadingVisible(false));
        mediaContainer.addView(videoPlayerView);

        loadingContainer = new FrameLayout(context);
        loadingContainer.setLayoutParams(new LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
        ));
        ProgressBar progressBar = new ProgressBar(context);
        LayoutParams progressLayoutParams = new LayoutParams(dp(28), dp(28), Gravity.CENTER);
        progressBar.setLayoutParams(progressLayoutParams);
        loadingContainer.addView(progressBar);
        loadingContainer.setVisibility(GONE);
        addView(loadingContainer);

        loadingPulseAnimator = ObjectAnimator.ofFloat(loadingContainer, View.ALPHA, 0.62f, 1f);
        loadingPulseAnimator.setDuration(760L);
        loadingPulseAnimator.setRepeatMode(ObjectAnimator.REVERSE);
        loadingPulseAnimator.setRepeatCount(ObjectAnimator.INFINITE);
    }

    public void setListener(@Nullable Listener listener) {
        this.listener = listener;
    }

    public void bind(@NonNull LevixelMediaItem item) {
        bindGeneration += 1;
        this.item = item;
        fullImageReady = false;
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            bindImage(item);
        } else {
            bindVideo(item);
        }
    }

    public void setActive(boolean active) {
        this.active = active;
        if (item == null || item.getMediaType() != LevixelMediaItem.MediaType.VIDEO) {
            return;
        }
        videoPlayerView.setActive(active);
    }

    public void release() {
        bindGeneration += 1;
        Glide.with(photoView.getContext().getApplicationContext()).clear(photoView);
        Glide.with(previewImageView.getContext().getApplicationContext()).clear(previewImageView);
        photoView.setImageDrawable(null);
        previewImageView.setImageDrawable(null);
        previewImageView.setVisibility(GONE);
        photoView.setScale(1f, false);
        photoView.setVisibility(GONE);
        videoPlayerView.release();
        videoPlayerView.setVisibility(GONE);
        item = null;
        active = false;
        fullImageReady = false;
        setLoadingVisible(false);
    }

    @NonNull
    public View getDragTarget() {
        return mediaContainer;
    }

    public boolean canPageHorizontally() {
        if (item == null) {
            return true;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            return photoView.getScale() <= 1.02f;
        }
        return true;
    }

    public void setAllowParentInterceptOnImageEdge(boolean allow) {
        allowParentInterceptOnImageEdge = allow;
        photoView.setAllowParentInterceptOnEdge(allow);
    }

    public boolean canBeginVerticalDismiss(float dx, float dy, float rawX, float rawY) {
        if (item == null) {
            return false;
        }
        if (Math.abs(dy) <= Math.abs(dx) * 1.02f) {
            return false;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            return photoView.getScale() <= 1.02f;
        }
        return !videoPlayerView.isTouchOnInteractiveControls(rawX, rawY);
    }

    public boolean isTouchOnInteractiveVideoControls(float rawX, float rawY) {
        return item != null
                && item.getMediaType() == LevixelMediaItem.MediaType.VIDEO
                && videoPlayerView.isTouchOnInteractiveControls(rawX, rawY);
    }

    public void setMediaHidden(boolean hidden) {
        if (item == null) {
            return;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            photoView.setAlpha(hidden ? 0f : 1f);
            previewImageView.setAlpha(hidden ? 0f : 1f);
        } else {
            videoPlayerView.setMediaHidden(hidden);
        }
    }

    public void setSourcePlaceholderIfNeeded(@Nullable Drawable drawable) {
        if (item == null || drawable == null) {
            return;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.VIDEO) {
            videoPlayerView.setPosterPlaceholder(drawable);
            return;
        }
        if (fullImageReady) {
            return;
        }
        Glide.with(previewImageView).clear(previewImageView);
        previewImageView.setImageDrawable(drawable);
        previewImageView.setVisibility(VISIBLE);
        setLoadingVisible(true);
    }

    @Nullable
    public LevixelSharedElementState sharedElementState() {
        if (item == null) {
            return null;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            if (previewImageView.getVisibility() == VISIBLE && previewImageView.getDrawable() != null) {
                return LevixelLayoutSupport.captureImageViewState(previewImageView);
            }
            return LevixelLayoutSupport.captureImageViewState(photoView);
        }
        return videoPlayerView.sharedElementState();
    }

    @NonNull
    public LevixelSharedElementGeometry defaultTransitionGeometry(@NonNull RectF containerBounds, @Nullable Drawable fallbackDrawable) {
        Drawable drawable = currentDrawable();
        if (drawable == null) {
            drawable = fallbackDrawable;
        }
        if (drawable == null) {
            float fallbackWidth = Math.max(containerBounds.width() * 0.72f, 1f);
            float fallbackHeight = Math.max(containerBounds.height() * 0.42f, 1f);
            float left = containerBounds.left + (containerBounds.width() - fallbackWidth) * 0.5f;
            float top = containerBounds.top + (containerBounds.height() - fallbackHeight) * 0.5f;
            RectF visibleFrame = new RectF(left, top, left + fallbackWidth, top + fallbackHeight);
            RectF contentFrame = new RectF(0f, 0f, visibleFrame.width(), visibleFrame.height());
            return new LevixelSharedElementGeometry(visibleFrame, contentFrame);
        }
        return LevixelLayoutSupport.defaultGeometryFor(drawable, containerBounds);
    }

    public void prepareForOpenTransition() {
        if (item == null) {
            return;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            photoView.setScale(1f, false);
            photoView.setAllowParentInterceptOnEdge(allowParentInterceptOnImageEdge);
        } else {
            videoPlayerView.prepareForReturnTransition();
        }
    }

    public void prepareForReturnTransition() {
        if (item == null) {
            return;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            photoView.setScale(1f, false);
            photoView.setAllowParentInterceptOnEdge(allowParentInterceptOnImageEdge);
        } else {
            videoPlayerView.prepareForReturnTransition();
        }
    }

    public void prepareForDismissDrag() {
        if (item == null) {
            return;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            photoView.setScale(1f, false);
        } else {
            videoPlayerView.prepareForReturnTransition();
        }
    }

    public void restoreAfterDismissCancelled() {
        if (item == null || item.getMediaType() != LevixelMediaItem.MediaType.VIDEO) {
            return;
        }
        videoPlayerView.restoreAfterDismissCancelled();
    }

    private void bindImage(@NonNull LevixelMediaItem item) {
        final int generation = bindGeneration;
        photoView.setVisibility(VISIBLE);
        photoView.setAlpha(1f);
        videoPlayerView.release();
        videoPlayerView.setVisibility(GONE);
        photoView.setScale(1f, false);
        photoView.setAllowParentInterceptOnEdge(allowParentInterceptOnImageEdge);
        Glide.with(photoView).clear(photoView);
        photoView.setImageDrawable(null);
        Glide.with(previewImageView).clear(previewImageView);
        previewImageView.setAlpha(1f);
        previewImageView.setVisibility(VISIBLE);
        previewImageView.setImageDrawable(null);
        Glide.with(previewImageView)
                .load(item.getThumbnailUrl())
                .dontAnimate()
                .listener(new RequestListener<Drawable>() {
                    @Override
                    public boolean onLoadFailed(@Nullable GlideException e, Object model, Target<Drawable> target, boolean isFirstResource) {
                        if (generation == bindGeneration && !fullImageReady) {
                            previewImageView.setVisibility(GONE);
                        }
                        return false;
                    }

                    @Override
                    public boolean onResourceReady(Drawable resource, Object model, Target<Drawable> target, com.bumptech.glide.load.DataSource dataSource, boolean isFirstResource) {
                        return generation != bindGeneration || fullImageReady;
                    }
                })
                .into(previewImageView);
        setLoadingVisible(true);
        Glide.with(photoView)
                .load(item.getSourceUrl())
                .dontAnimate()
                .listener(new RequestListener<Drawable>() {
                    @Override
                    public boolean onLoadFailed(@Nullable GlideException e, Object model, Target<Drawable> target, boolean isFirstResource) {
                        if (generation == bindGeneration) {
                            setLoadingVisible(false);
                        }
                        return false;
                    }

                    @Override
                    public boolean onResourceReady(Drawable resource, Object model, Target<Drawable> target, com.bumptech.glide.load.DataSource dataSource, boolean isFirstResource) {
                        if (generation != bindGeneration) {
                            return true;
                        }
                        fullImageReady = true;
                        applyDynamicPhotoScaleBounds(generation, true);
                        return false;
                    }
                })
                .into(photoView);
    }

    private void applyDynamicPhotoScaleBounds(int generation, boolean completePreviewHandoff) {
        photoView.getViewTreeObserver().addOnPreDrawListener(new ViewTreeObserver.OnPreDrawListener() {
            @Override
            public boolean onPreDraw() {
                photoView.getViewTreeObserver().removeOnPreDrawListener(this);
                if (generation != bindGeneration) {
                    return true;
                }
                RectF displayRect = photoView.getDisplayRect();
                if (displayRect == null || displayRect.width() <= 0f || displayRect.height() <= 0f) {
                    return true;
                }

                float fillWidthScale = photoView.getWidth() > 0 ? photoView.getWidth() / displayRect.width() : 1f;
                float fillHeightScale = photoView.getHeight() > 0 ? photoView.getHeight() / displayRect.height() : 1f;
                float coverViewportScale = Math.max(fillWidthScale, fillHeightScale);
                float maximumScale = Math.max(4f, Math.min(coverViewportScale * 3f, 32f));
                float mediumScale = Math.min(Math.max(2f, coverViewportScale), maximumScale * 0.5f);

                photoView.setScaleLevels(1f, mediumScale, maximumScale);
                if (completePreviewHandoff) {
                    photoView.postOnAnimation(() -> {
                        if (generation != bindGeneration) {
                            return;
                        }
                        previewImageView.setVisibility(GONE);
                        previewImageView.setImageDrawable(null);
                        setLoadingVisible(false);
                    });
                }
                return true;
            }
        });
    }

    private void bindVideo(@NonNull LevixelMediaItem item) {
        photoView.setVisibility(GONE);
        Glide.with(photoView).clear(photoView);
        photoView.setImageDrawable(null);
        Glide.with(previewImageView).clear(previewImageView);
        previewImageView.setImageDrawable(null);
        previewImageView.setVisibility(GONE);
        videoPlayerView.setVisibility(VISIBLE);
        videoPlayerView.setMediaHidden(false);
        videoPlayerView.bind(item);
        videoPlayerView.setActive(active);
        setLoadingVisible(true);
    }

    @Nullable
    private Drawable currentDrawable() {
        if (item == null) {
            return null;
        }
        if (item.getMediaType() == LevixelMediaItem.MediaType.IMAGE) {
            if (previewImageView.getVisibility() == VISIBLE && previewImageView.getDrawable() != null) {
                return previewImageView.getDrawable();
            }
            return photoView.getDrawable();
        }
        return videoPlayerView.getPosterDrawable();
    }

    private void setLoadingVisible(boolean visible) {
        if (visible) {
            loadingContainer.setVisibility(VISIBLE);
            if (!loadingPulseAnimator.isRunning()) {
                loadingPulseAnimator.start();
            }
            return;
        }
        loadingPulseAnimator.cancel();
        loadingContainer.setAlpha(1f);
        loadingContainer.setVisibility(GONE);
    }

    private int dp(int value) {
        return (int) TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                value,
                getResources().getDisplayMetrics()
        );
    }
}
