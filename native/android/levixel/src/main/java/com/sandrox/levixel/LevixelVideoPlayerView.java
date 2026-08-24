package com.sandrox.levixel;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.content.res.AppCompatResources;
import androidx.appcompat.widget.AppCompatImageButton;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.common.PlaybackException;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.PlayerControlView;
import androidx.media3.ui.PlayerView;

import com.bumptech.glide.Glide;

public final class LevixelVideoPlayerView extends FrameLayout {
    public interface Listener {
        void onCloseRequested();
    }

    private final ImageView posterImageView;
    private final PlayerView playerView;
    private final AppCompatImageButton closeButton;
    @Nullable
    private Runnable contentReadyListener;
    @Nullable
    private LevixelMediaItem item;
    @Nullable
    private ExoPlayer player;
    @Nullable
    private String preparedSourceUrl;
    @Nullable
    private Listener listener;
    private boolean firstFrameReady;
    private boolean active;

    private final Player.Listener playerListener = new Player.Listener() {
        @Override
        public void onRenderedFirstFrame() {
            firstFrameReady = true;
            notifyContentReady();
            if (active) {
                revealPlayer();
            }
        }

        @Override
        public void onPlayerError(@NonNull PlaybackException error) {
            firstFrameReady = false;
            notifyContentReady();
        }
    };

    public LevixelVideoPlayerView(@NonNull Context context) {
        super(context);
        setLayoutParams(new LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        setBackgroundColor(Color.TRANSPARENT);

        posterImageView = new ImageView(context);
        posterImageView.setLayoutParams(new LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        posterImageView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        posterImageView.setBackgroundColor(Color.TRANSPARENT);
        addView(posterImageView);

        playerView = (PlayerView) LayoutInflater.from(context)
                .inflate(R.layout.levixel_player_view, this, false);
        playerView.setUseController(true);
        playerView.setControllerAutoShow(true);
        playerView.setControllerHideOnTouch(true);
        playerView.setShutterBackgroundColor(Color.TRANSPARENT);
        playerView.setBackgroundColor(Color.TRANSPARENT);
        playerView.setShowPreviousButton(false);
        playerView.setShowNextButton(false);
        playerView.setShowRewindButton(false);
        playerView.setShowFastForwardButton(false);
        playerView.setShowSubtitleButton(false);
        playerView.setShowVrButton(false);
        playerView.setShowShuffleButton(false);
        playerView.setAlpha(0f);
        playerView.setVisibility(VISIBLE);
        addView(playerView);
        hideControllerView(androidx.media3.ui.R.id.exo_settings);
        hideControllerView(androidx.media3.ui.R.id.exo_overflow_show);
        hideControllerView(androidx.media3.ui.R.id.exo_overflow_hide);

        closeButton = new AppCompatImageButton(context);
        LayoutParams closeLayoutParams = new LayoutParams(dp(48), dp(48));
        closeLayoutParams.gravity = Gravity.TOP | Gravity.START;
        closeLayoutParams.topMargin = dp(14);
        closeLayoutParams.leftMargin = dp(10);
        closeButton.setLayoutParams(closeLayoutParams);
        closeButton.setImageDrawable(
                AppCompatResources.getDrawable(context, androidx.appcompat.R.drawable.abc_ic_clear_material)
        );
        closeButton.setBackgroundResource(resolveSelectableItemBackgroundBorderless());
        closeButton.setImageTintList(ColorStateList.valueOf(Color.WHITE));
        closeButton.setPadding(dp(12), dp(12), dp(12), dp(12));
        closeButton.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        closeButton.setVisibility(GONE);
        closeButton.setOnClickListener(v -> {
            if (listener != null) {
                listener.onCloseRequested();
            }
        });
        addView(closeButton);

        playerView.setControllerVisibilityListener((PlayerControlView.VisibilityListener) visibility -> {
            if (firstFrameReady) {
                closeButton.setVisibility(visibility == View.VISIBLE ? View.VISIBLE : View.GONE);
            }
        });
    }

    public void setListener(@Nullable Listener listener) {
        this.listener = listener;
    }

    public void setOnContentReadyListener(@Nullable Runnable contentReadyListener) {
        this.contentReadyListener = contentReadyListener;
    }

    public void bind(@NonNull LevixelMediaItem item) {
        this.item = item;
        firstFrameReady = false;
        playerView.animate().cancel();
        playerView.setAlpha(0f);
        playerView.setVisibility(VISIBLE);
        closeButton.setVisibility(GONE);
        posterImageView.animate().cancel();
        posterImageView.setAlpha(1f);
        posterImageView.setVisibility(VISIBLE);
        Glide.with(posterImageView).clear(posterImageView);
        posterImageView.setImageDrawable(null);
        Glide.with(posterImageView)
                .load(item.getThumbnailUrl())
                .dontAnimate()
                .into(posterImageView);
        if (active) {
            ensurePlayerPrepared(item.getSourceUrl());
        }
    }

    public void setActive(boolean active) {
        this.active = active;
        if (item == null) {
            return;
        }
        if (active) {
            ensurePlayerPrepared(item.getSourceUrl());
            if (player != null) {
                player.play();
            }
            if (firstFrameReady) {
                revealPlayer();
            }
        } else {
            if (player != null) {
                player.pause();
            }
            closeButton.setVisibility(GONE);
        }
    }

    public void setMediaHidden(boolean hidden) {
        setAlpha(hidden ? 0f : 1f);
    }

    @Nullable
    public LevixelSharedElementState sharedElementState() {
        return LevixelLayoutSupport.captureImageViewState(posterImageView);
    }

    @Nullable
    public Drawable getPosterDrawable() {
        return posterImageView.getDrawable();
    }

    public void prepareForReturnTransition() {
        playerView.animate().cancel();
        posterImageView.animate().cancel();
        posterImageView.setAlpha(1f);
        posterImageView.setVisibility(VISIBLE);
        playerView.setAlpha(0f);
        playerView.setVisibility(VISIBLE);
        closeButton.setVisibility(GONE);
    }

    public void restoreAfterDismissCancelled() {
        if (!firstFrameReady) {
            prepareForReturnTransition();
            return;
        }
        playerView.setVisibility(VISIBLE);
        playerView.setAlpha(1f);
        posterImageView.setVisibility(VISIBLE);
        posterImageView.setAlpha(0f);
    }

    public boolean isTouchOnInteractiveControls(float rawX, float rawY) {
        return isTouchInsideView(playerView.findViewById(androidx.media3.ui.R.id.exo_bottom_bar), rawX, rawY, dp(16))
                || isTouchInsideView(playerView.findViewById(androidx.media3.ui.R.id.exo_progress), rawX, rawY, dp(24))
                || isTouchInsideView(closeButton, rawX, rawY, dp(12));
    }

    public void setPosterPlaceholder(@NonNull Drawable drawable) {
        if (firstFrameReady) {
            return;
        }
        Glide.with(posterImageView).clear(posterImageView);
        posterImageView.setImageDrawable(drawable);
        posterImageView.setAlpha(1f);
        posterImageView.setVisibility(VISIBLE);
    }

    public void release() {
        Glide.with(posterImageView.getContext().getApplicationContext()).clear(posterImageView);
        posterImageView.setImageDrawable(null);
        posterImageView.animate().cancel();
        posterImageView.setAlpha(1f);
        posterImageView.setVisibility(VISIBLE);
        closeButton.setVisibility(GONE);
        if (player != null) {
            player.removeListener(playerListener);
            player.release();
            player = null;
            playerView.setPlayer(null);
        }
        playerView.animate().cancel();
        playerView.setAlpha(0f);
        playerView.setVisibility(VISIBLE);
        preparedSourceUrl = null;
        firstFrameReady = false;
    }

    private void ensurePlayerPrepared(@NonNull String sourceUrl) {
        if (player == null) {
            player = new ExoPlayer.Builder(getContext()).build();
            player.addListener(playerListener);
            playerView.setPlayer(player);
        }
        if (sourceUrl.equals(preparedSourceUrl)) {
            return;
        }
        firstFrameReady = false;
        playerView.animate().cancel();
        playerView.setAlpha(0f);
        playerView.setVisibility(VISIBLE);
        closeButton.setVisibility(GONE);
        player.setMediaItem(MediaItem.fromUri(Uri.parse(sourceUrl)));
        player.prepare();
        preparedSourceUrl = sourceUrl;
    }

    private void revealPlayer() {
        playerView.setVisibility(VISIBLE);
        playerView.animate().cancel();
        playerView.setAlpha(0f);
        posterImageView.animate().cancel();
        posterImageView.setVisibility(VISIBLE);
        posterImageView.setAlpha(1f);
        playerView.animate()
                .alpha(1f)
                .setDuration(180L)
                .start();
        posterImageView.animate()
                .alpha(0f)
                .setDuration(220L)
                .withEndAction(() -> {
                    if (playerView.isControllerFullyVisible()) {
                        closeButton.setVisibility(VISIBLE);
                    }
                })
                .start();
    }

    private void notifyContentReady() {
        if (contentReadyListener != null) {
            contentReadyListener.run();
        }
    }

    private void hideControllerView(int viewId) {
        View target = playerView.findViewById(viewId);
        if (target != null) {
            target.setVisibility(GONE);
        }
    }

    private boolean isTouchInsideView(@Nullable View target, float rawX, float rawY, int extraPaddingPx) {
        if (target == null || !target.isShown() || target.getWidth() <= 0 || target.getHeight() <= 0) {
            return false;
        }
        int[] location = new int[2];
        target.getLocationOnScreen(location);
        Rect hitRect = new Rect(
                location[0] - extraPaddingPx,
                location[1] - extraPaddingPx,
                location[0] + target.getWidth() + extraPaddingPx,
                location[1] + target.getHeight() + extraPaddingPx
        );
        return hitRect.contains(Math.round(rawX), Math.round(rawY));
    }

    private int resolveSelectableItemBackgroundBorderless() {
        TypedValue outValue = new TypedValue();
        boolean resolved = getContext().getTheme().resolveAttribute(
                android.R.attr.selectableItemBackgroundBorderless,
                outValue,
                true
        );
        return resolved ? outValue.resourceId : 0;
    }

    private int dp(int value) {
        return (int) TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                value,
                getResources().getDisplayMetrics()
        );
    }
}
