package com.sandrox.levixel.uniapp.runtime;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsControllerCompat;

final class LevixelUniViewerWindow {
    interface Listener {
        void onBackRequested();

        void onWindowDismissed();
    }

    @NonNull private final Dialog dialog;
    @NonNull private final FrameLayout contentHost;
    @NonNull private final Listener listener;
    private final boolean lightTheme;
    @Nullable private Object backCallback;
    private boolean attached;
    private boolean dismissed;

    LevixelUniViewerWindow(
            @NonNull Activity activity,
            boolean lightTheme,
            @NonNull Listener listener
    ) {
        this.listener = listener;
        this.lightTheme = lightTheme;
        contentHost = new FrameLayout(activity);
        contentHost.setLayoutParams(new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        contentHost.setBackgroundColor(Color.TRANSPARENT);
        contentHost.setFitsSystemWindows(false);
        contentHost.setClickable(true);
        contentHost.setFocusable(true);
        contentHost.setFocusableInTouchMode(true);
        contentHost.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override
            public void onViewAttachedToWindow(@NonNull View view) {
                attached = true;
            }

            @Override
            public void onViewDetachedFromWindow(@NonNull View view) {
                if (attached) {
                    handleUnexpectedDismiss();
                }
            }
        });

        dialog = new ViewerDialog(activity, listener::onBackRequested);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setCancelable(false);
        dialog.setCanceledOnTouchOutside(false);
        dialog.setContentView(contentHost);
        dialog.setOnDismissListener(ignored -> handleUnexpectedDismiss());
    }

    boolean show() {
        Activity activity = dialog.getOwnerActivity();
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            return false;
        }
        Window window = dialog.getWindow();
        if (window == null) {
            return false;
        }
        configure(window);
        try {
            dialog.show();
        } catch (WindowManager.BadTokenException exception) {
            dismissed = true;
            return false;
        }
        window.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        );
        configure(window);
        registerBackCallback();
        contentHost.requestFocus();
        return true;
    }

    void setContent(@NonNull View content) {
        if (dismissed) {
            throw new IllegalStateException("Cannot attach content to a dismissed Levixel window.");
        }
        contentHost.removeAllViews();
        contentHost.addView(content, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
    }

    void dismiss() {
        if (dismissed) {
            return;
        }
        dismissed = true;
        unregisterBackCallback();
        dialog.setOnDismissListener(null);
        if (dialog.isShowing()) {
            dialog.dismiss();
        }
    }

    @SuppressWarnings("deprecation")
    private void configure(@NonNull Window window) {
        window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        window.clearFlags(
                WindowManager.LayoutParams.FLAG_DIM_BEHIND
                        | WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS
                        | WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION
        );
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            WindowManager.LayoutParams attributes = window.getAttributes();
            attributes.layoutInDisplayCutoutMode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                    ? WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                    : WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            attributes.width = ViewGroup.LayoutParams.MATCH_PARENT;
            attributes.height = ViewGroup.LayoutParams.MATCH_PARENT;
            attributes.gravity = Gravity.FILL;
            attributes.dimAmount = 0f;
            attributes.windowAnimations = 0;
            window.setAttributes(attributes);
        } else {
            WindowManager.LayoutParams attributes = window.getAttributes();
            attributes.width = ViewGroup.LayoutParams.MATCH_PARENT;
            attributes.height = ViewGroup.LayoutParams.MATCH_PARENT;
            attributes.gravity = Gravity.FILL;
            attributes.dimAmount = 0f;
            attributes.windowAnimations = 0;
            window.setAttributes(attributes);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.setNavigationBarDividerColor(Color.TRANSPARENT);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.setStatusBarContrastEnforced(false);
            window.setNavigationBarContrastEnforced(false);
        }

        WindowCompat.setDecorFitsSystemWindows(window, false);
        WindowInsetsControllerCompat controller = WindowCompat.getInsetsController(
                window,
                window.getDecorView()
        );
        controller.setAppearanceLightStatusBars(lightTheme);
        controller.setAppearanceLightNavigationBars(lightTheme);
    }

    private void handleUnexpectedDismiss() {
        if (dismissed) {
            return;
        }
        dismissed = true;
        unregisterBackCallback();
        listener.onWindowDismissed();
    }

    private void registerBackCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || backCallback != null) {
            return;
        }
        backCallback = Api33BackHandler.register(dialog, listener::onBackRequested);
    }

    private void unregisterBackCallback() {
        Object callback = backCallback;
        backCallback = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && callback != null) {
            Api33BackHandler.unregister(dialog, callback);
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private static final class Api33BackHandler {
        @NonNull
        static Object register(@NonNull Dialog dialog, @NonNull Runnable action) {
            OnBackInvokedCallback callback = action::run;
            dialog.getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                    callback
            );
            return callback;
        }

        static void unregister(@NonNull Dialog dialog, @NonNull Object callback) {
            dialog.getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(
                    (OnBackInvokedCallback) callback
            );
        }

        private Api33BackHandler() {
        }
    }

    @SuppressWarnings("deprecation")
    private static final class ViewerDialog extends Dialog {
        @NonNull private final Runnable backAction;

        ViewerDialog(@NonNull Activity activity, @NonNull Runnable backAction) {
            super(activity, android.R.style.Theme_Translucent_NoTitleBar);
            this.backAction = backAction;
            setOwnerActivity(activity);
        }

        @Override
        public void onBackPressed() {
            backAction.run();
        }
    }
}
