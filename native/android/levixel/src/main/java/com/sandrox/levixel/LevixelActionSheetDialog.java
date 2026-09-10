package com.sandrox.levixel;

import android.content.Context;
import android.os.Build;
import android.view.Window;
import androidx.annotation.Nullable;
import com.google.android.material.bottomsheet.BottomSheetBehavior;
import com.google.android.material.bottomsheet.BottomSheetDialog;
import java.util.ArrayList;
import java.util.List;

final class LevixelActionSheetDialog extends BottomSheetDialog {
    interface Closed { void close(@Nullable LevixelAction selected); }
    private final List<Runnable> completions = new ArrayList<>();
    @Nullable private LevixelAction selected;
    private boolean closing;
    private boolean closed;

    LevixelActionSheetDialog(Context context, List<LevixelAction> actions,
            LevixelActionLayout layout, boolean listIcons, Closed onClosed) {
        // The action surface has its own appearance, independent of the media canvas.
        super(context, R.style.Levixel_ActionSheet_Light);
        setContentView(new LevixelActionSheetView(getContext(), actions, layout, listIcons, action -> {
            if (closing || action.disabled) return;
            selected = action;
            close(null);
        }, () -> close(null)));
        setDismissWithAnimation(true);
        setCanceledOnTouchOutside(true);
        getBehavior().setSkipCollapsed(true);
        getBehavior().setShouldRemoveExpandedCorners(false);
        // Choose the resting state before the first layout/window animation.
        // Changing it from onShow/post() produces two competing movements.
        getBehavior().setState(BottomSheetBehavior.STATE_EXPANDED);
        setOnDismissListener(dialog -> {
            if (closed) return;
            closed = true;
            onClosed.close(selected);
            List<Runnable> callbacks = new ArrayList<>(completions);
            completions.clear();
            for (Runnable callback : callbacks) callback.run();
        });
    }

    @Override public void onAttachedToWindow() {
        super.onAttachedToWindow();
        Window window = getWindow();
        if (window != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Keep the sheet surface visible beneath the transparent navigation bar.
            window.setNavigationBarContrastEnforced(false);
        }
    }

    @Override public void cancel() {
        closing = true;
        // Material calls cancel again after reaching STATE_HIDDEN.
        super.cancel();
    }

    void close(@Nullable Runnable completion) {
        if (closed) { if (completion != null) completion.run(); return; }
        if (completion != null) completions.add(completion);
        if (!closing) cancel();
    }

    void dismissImmediately() {
        closing = true;
        selected = null;
        setDismissWithAnimation(false);
        if (getWindow() != null) getWindow().setWindowAnimations(0);
        dismiss();
    }
}
