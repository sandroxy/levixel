package com.sandrox.levixel.uniapp.runtime;

import android.app.Activity;
import android.graphics.RectF;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

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
    @NonNull private final View viewportView;
    @NonNull private final LevixelUniContract.OpenRequest request;
    @NonNull private final Listener listener;
    @NonNull private final List<LevixelMediaItem> nativeItems;
    @NonNull private final String galleryId = "uni-levixel-" + UUID.randomUUID();

    @Nullable private LevixelViewerOverlayView overlayView;
    @Nullable private LevixelUniViewerWindow viewerWindow;
    private int currentIndex;
    private boolean opened;
    private boolean finished;

    LevixelUniSession(
            @NonNull Activity activity,
            @NonNull View viewportView,
            @NonNull LevixelUniContract.OpenRequest request,
            @NonNull Listener listener
    ) {
        this.activity = activity;
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
        viewportView.postOnAnimation(this::openOverlay);
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
        LevixelUniViewerWindow window = new LevixelUniViewerWindow(
                activity,
                request.lightTheme,
                new LevixelUniViewerWindow.Listener() {
                    @Override
                    public void onBackRequested() {
                        close(true);
                    }

                    @Override
                    public void onWindowDismissed() {
                        viewerWindow = null;
                        overlayView = null;
                        finish(opened);
                    }
                }
        );
        viewerWindow = window;
        if (!window.show()) {
            viewerWindow = null;
            finish(false);
            return;
        }
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
        window.setContent(overlay);
        opened = true;
        listener.onOpened(this);
    }

    private void finish(boolean emitDismissEvent) {
        if (finished) {
            return;
        }
        finished = true;
        LevixelUniViewerWindow window = viewerWindow;
        viewerWindow = null;
        if (window != null) {
            window.dismiss();
        }

        if (!opened) {
            listener.onOpenCancelled(this);
        }
        listener.onDismissed(this, emitDismissEvent && opened);
    }
}
