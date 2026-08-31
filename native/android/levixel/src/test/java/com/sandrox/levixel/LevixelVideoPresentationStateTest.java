package com.sandrox.levixel;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class LevixelVideoPresentationStateTest {
    @Test
    public void repeatedFirstFrameAfterSeekDoesNotRestartHandoff() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();

        LevixelVideoPresentationState.FrameUpdate initial = state.onFrameRendered(true);
        LevixelVideoPresentationState.FrameUpdate afterSeek = state.onFrameRendered(true);

        assertTrue(initial.contentBecameReady());
        assertTrue(initial.shouldRevealPlayer());
        assertFalse(afterSeek.contentBecameReady());
        assertFalse(afterSeek.shouldRevealPlayer());
        assertTrue(state.isPlayerPresented());
    }

    @Test
    public void inactiveFirstFrameWaitsForActivation() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();

        LevixelVideoPresentationState.FrameUpdate frame = state.onFrameRendered(false);

        assertTrue(frame.contentBecameReady());
        assertFalse(frame.shouldRevealPlayer());
        assertTrue(state.onActivated());
        assertFalse(state.onActivated());
        assertTrue(state.isPlayerPresented());
    }

    @Test
    public void pageReactivationDoesNotRestartHandoff() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();

        assertTrue(state.onFrameRendered(true).shouldRevealPlayer());

        assertFalse(state.onActivated());
        assertTrue(state.isPlayerPresented());
    }

    @Test
    public void transitionPosterSuppressesRendererCallbacksUntilDismissIsCancelled() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();
        state.onFrameRendered(true);

        state.forcePosterForTransition();
        LevixelVideoPresentationState.FrameUpdate duringTransition = state.onFrameRendered(true);

        assertFalse(duringTransition.contentBecameReady());
        assertFalse(duringTransition.shouldRevealPlayer());
        assertFalse(state.isPlayerPresented());
        assertTrue(state.restoreAfterDismissCancelled());
        assertTrue(state.isPlayerPresented());
    }

    @Test
    public void cancellingDismissBeforeFirstFrameUnlocksFutureHandoff() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();
        state.forcePosterForTransition();

        assertFalse(state.restoreAfterDismissCancelled());

        LevixelVideoPresentationState.FrameUpdate frame = state.onFrameRendered(true);
        assertTrue(frame.contentBecameReady());
        assertTrue(frame.shouldRevealPlayer());
    }

    @Test
    public void newMediaCanPerformItsOwnInitialHandoff() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();
        state.onFrameRendered(true);

        state.resetForMedia();

        LevixelVideoPresentationState.FrameUpdate frame = state.onFrameRendered(true);
        assertTrue(frame.contentBecameReady());
        assertTrue(frame.shouldRevealPlayer());
    }

    @Test
    public void playbackErrorSettlesLoadingOnceAndLaterFrameCanRecover() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();

        assertTrue(state.onPlayerError());
        assertFalse(state.onPlayerError());

        LevixelVideoPresentationState.FrameUpdate recovered = state.onFrameRendered(true);
        assertFalse(recovered.contentBecameReady());
        assertTrue(recovered.shouldRevealPlayer());
        assertTrue(state.isPlayerPresented());
    }

    @Test
    public void playbackErrorAfterAFrameDoesNotReturnToPoster() {
        LevixelVideoPresentationState state = new LevixelVideoPresentationState();
        state.onFrameRendered(true);

        assertFalse(state.onPlayerError());
        assertTrue(state.isFrameReady());
        assertTrue(state.isPlayerPresented());
    }
}
