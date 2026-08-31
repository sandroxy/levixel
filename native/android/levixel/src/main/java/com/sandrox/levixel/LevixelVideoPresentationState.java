package com.sandrox.levixel;

/**
 * Owns the poster-to-player handoff for one prepared video source.
 *
 * <p>Media3 may report a rendered first frame again after operations such as seeking. The
 * presentation handoff must therefore be idempotent rather than tied directly to every renderer
 * callback.</p>
 */
final class LevixelVideoPresentationState {
    static final class FrameUpdate {
        private final boolean contentBecameReady;
        private final boolean shouldRevealPlayer;

        FrameUpdate(boolean contentBecameReady, boolean shouldRevealPlayer) {
            this.contentBecameReady = contentBecameReady;
            this.shouldRevealPlayer = shouldRevealPlayer;
        }

        boolean contentBecameReady() {
            return contentBecameReady;
        }

        boolean shouldRevealPlayer() {
            return shouldRevealPlayer;
        }
    }

    private boolean contentSettled;
    private boolean frameReady;
    private boolean playerPresented;
    private boolean transitionPosterForced;

    void resetForMedia() {
        contentSettled = false;
        frameReady = false;
        playerPresented = false;
        transitionPosterForced = false;
    }

    FrameUpdate onFrameRendered(boolean active) {
        boolean contentBecameReady = !contentSettled;
        contentSettled = true;
        frameReady = true;
        return new FrameUpdate(contentBecameReady, claimPlayerPresentation(active));
    }

    boolean onPlayerError() {
        if (contentSettled) {
            return false;
        }
        contentSettled = true;
        return true;
    }

    boolean onActivated() {
        transitionPosterForced = false;
        return claimPlayerPresentation(true);
    }

    void forcePosterForTransition() {
        transitionPosterForced = true;
        playerPresented = false;
    }

    boolean restoreAfterDismissCancelled() {
        transitionPosterForced = false;
        if (!frameReady) {
            return false;
        }
        playerPresented = true;
        return true;
    }

    boolean isContentSettled() {
        return contentSettled;
    }

    boolean isFrameReady() {
        return frameReady;
    }

    boolean isPlayerPresented() {
        return frameReady && playerPresented && !transitionPosterForced;
    }

    private boolean claimPlayerPresentation(boolean active) {
        if (!active || !frameReady || playerPresented || transitionPosterForced) {
            return false;
        }
        playerPresented = true;
        return true;
    }
}
