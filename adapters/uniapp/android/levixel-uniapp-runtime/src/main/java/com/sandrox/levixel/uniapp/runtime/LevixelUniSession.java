package com.sandrox.levixel.uniapp.runtime;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.RectF;
import android.os.Build;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.sandrox.levixel.LevixelLayoutSupport;
import com.sandrox.levixel.LevixelMediaItem;
import com.sandrox.levixel.LevixelSourceHint;
import com.sandrox.levixel.LevixelViewerOverlayView;

import java.util.List;
import java.util.UUID;

final class LevixelUniSession {
    interface Listener {
        void onOpened(@NonNull LevixelUniSession session);

        void onOpenCancelled(@NonNull LevixelUniSession session);

        void onIndexChange(@NonNull LevixelUniSession session, int previousIndex, int currentIndex);

        void onDismissed(@NonNull LevixelUniSession session, boolean emitDismissEvent);
    }

    @NonNull private final Activity activity;
    @NonNull private final ViewGroup decorHost;
    @NonNull private final View viewportView;
    @NonNull private final LevixelUniContract.OpenRequest request;
    @NonNull private final Listener listener;
    @NonNull private final List<LevixelMediaItem> nativeItems;
    @NonNull private final String galleryId = "uni-levixel-" + UUID.randomUUID();
    @NonNull private final WindowStyle windowStyle = new WindowStyle();

    @Nullable private LevixelViewerOverlayView overlayView;
    private int currentIndex;
    private boolean opened;
    private boolean finished;

    LevixelUniSession(
            @NonNull Activity activity,
            @NonNull ViewGroup decorHost,
            @NonNull View viewportView,
            @NonNull LevixelUniContract.OpenRequest request,
            @NonNull Listener listener
    ) {
        this.activity = activity;
        this.decorHost = decorHost;
        this.viewportView = viewportView;
        this.request = request;
        this.listener = listener;
        nativeItems = request.nativeItems();
        currentIndex = request.initialIndex;
    }

    void start() {
        if (finished) {
            return;
        }
        windowStyle.apply(activity.getWindow(), request.lightTheme);
        decorHost.postOnAnimation(this::openOverlay);
    }

    void close(boolean animated) {
        if (finished) {
            return;
        }
        LevixelViewerOverlayView overlay = overlayView;
        if (overlay == null) {
            finish(false);
            return;
        }
        if (animated) {
            overlay.requestClose();
        } else {
            overlay.dismissImmediately();
        }
    }

    @NonNull
    String galleryId() {
        return galleryId;
    }

    int currentIndex() {
        return currentIndex;
    }

    int itemCount() {
        return request.items.size();
    }

    @NonNull
    String itemIdAt(int index) {
        return request.items.get(index).id;
    }

    boolean hidesHtmlSource() {
        return request.hidesHtmlSource;
    }

    private void openOverlay() {
        if (opened || finished) {
            return;
        }

        RectF viewportFrame = LevixelLayoutSupport.viewBoundsOnScreen(viewportView);
        RectF visibleViewportFrame = LevixelUniViewport.visibleFrameInWindow(viewportView);
        float fallbackRectScale = activity.getResources().getDisplayMetrics().density;
        List<LevixelSourceHint> sourceHints = LevixelUniSourceHints.map(
                request.sourceHints,
                viewportFrame,
                visibleViewportFrame,
                fallbackRectScale
        );
        LevixelViewerOverlayView overlay = new LevixelViewerOverlayView(
                activity,
                nativeItems,
                sourceHints,
                request.initialIndex,
                request.lightTheme,
                galleryId,
                new LevixelViewerOverlayView.Listener() {
                    @Override
                    public void onOverlayDismissed() {
                        overlayView = null;
                        finish(true);
                    }

                    @Override
                    public void onOverlayIndexChange(int index) {
                        if (finished || index == currentIndex) {
                            return;
                        }
                        int previousIndex = currentIndex;
                        currentIndex = index;
                        listener.onIndexChange(LevixelUniSession.this, previousIndex, index);
                    }
                }
        );
        overlayView = overlay;
        opened = true;
        decorHost.addView(overlay);
        listener.onOpened(this);
    }

    private void finish(boolean emitDismissEvent) {
        if (finished) {
            return;
        }
        finished = true;
        windowStyle.restore();

        if (!opened) {
            listener.onOpenCancelled(this);
        }
        listener.onDismissed(this, emitDismissEvent && opened);
    }

    private static final class WindowStyle {
        @Nullable private Window window;
        private int statusBarColor;
        private int navigationBarColor;
        private int systemUiVisibility;
        private boolean statusBarContrastEnforced;
        private boolean navigationBarContrastEnforced;
        private boolean applied;

        void apply(@Nullable Window targetWindow, boolean lightTheme) {
            if (targetWindow == null || applied) {
                return;
            }
            window = targetWindow;
            statusBarColor = targetWindow.getStatusBarColor();
            navigationBarColor = targetWindow.getNavigationBarColor();
            View decorView = targetWindow.getDecorView();
            systemUiVisibility = decorView.getSystemUiVisibility();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                statusBarContrastEnforced = targetWindow.isStatusBarContrastEnforced();
                navigationBarContrastEnforced = targetWindow.isNavigationBarContrastEnforced();
                targetWindow.setStatusBarContrastEnforced(false);
                targetWindow.setNavigationBarContrastEnforced(false);
            }

            targetWindow.setStatusBarColor(Color.TRANSPARENT);
            targetWindow.setNavigationBarColor(Color.TRANSPARENT);
            decorView.setSystemUiVisibility(systemUiVisibility
                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
            WindowInsetsControllerCompat controller = ViewCompat.getWindowInsetsController(decorView);
            if (controller != null) {
                controller.setAppearanceLightStatusBars(lightTheme);
                controller.setAppearanceLightNavigationBars(lightTheme);
            }
            applied = true;
        }

        void restore() {
            Window targetWindow = window;
            if (!applied || targetWindow == null) {
                return;
            }
            targetWindow.setStatusBarColor(statusBarColor);
            targetWindow.setNavigationBarColor(navigationBarColor);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                targetWindow.setStatusBarContrastEnforced(statusBarContrastEnforced);
                targetWindow.setNavigationBarContrastEnforced(navigationBarContrastEnforced);
            }
            targetWindow.getDecorView().setSystemUiVisibility(systemUiVisibility);
            applied = false;
            window = null;
        }
    }
}
