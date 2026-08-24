package com.sandrox.levixel.uniapp;

import android.graphics.Rect;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

final class LevixelUniViewport {
    private LevixelUniViewport() {
    }

    @NonNull
    static View resolve(@NonNull View rootView) {
        Candidate candidate = findBestWebView(rootView, null);
        return candidate != null ? candidate.view : rootView;
    }

    @Nullable
    private static Candidate findBestWebView(@NonNull View view, @Nullable Candidate best) {
        Candidate result = best;
        if (view instanceof WebView && isUsable(view)) {
            long visibleArea = visibleArea(view);
            if (visibleArea > 0 && (result == null || visibleArea >= result.visibleArea)) {
                result = new Candidate(view, visibleArea);
            }
        }
        if (!(view instanceof ViewGroup)) {
            return result;
        }

        ViewGroup group = (ViewGroup) view;
        for (int index = 0; index < group.getChildCount(); index++) {
            result = findBestWebView(group.getChildAt(index), result);
        }
        return result;
    }

    private static boolean isUsable(@NonNull View view) {
        return view.isAttachedToWindow()
                && view.isShown()
                && view.getAlpha() > 0.01f
                && view.getWidth() > 1
                && view.getHeight() > 1;
    }

    private static long visibleArea(@NonNull View view) {
        Rect visibleRect = new Rect();
        if (!view.getGlobalVisibleRect(visibleRect) || visibleRect.isEmpty()) {
            return 0L;
        }
        return (long) visibleRect.width() * visibleRect.height();
    }

    private static final class Candidate {
        @NonNull final View view;
        final long visibleArea;

        Candidate(@NonNull View view, long visibleArea) {
            this.view = view;
            this.visibleArea = visibleArea;
        }
    }
}
