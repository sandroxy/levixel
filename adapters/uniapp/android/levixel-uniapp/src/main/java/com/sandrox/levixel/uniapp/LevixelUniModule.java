package com.sandrox.levixel.uniapp;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.Map;

import io.dcloud.feature.uniapp.annotation.UniJSMethod;
import io.dcloud.feature.uniapp.bridge.UniJSCallback;
import io.dcloud.feature.uniapp.common.UniModule;

public final class LevixelUniModule extends UniModule implements LevixelUniSession.Listener {
    @Nullable private LevixelUniSession activeSession;
    @Nullable private UniJSCallback eventCallback;
    @Nullable private UniJSCallback pendingOpenCallback;

    @UniJSMethod(uiThread = true)
    public void onEvent(@Nullable UniJSCallback callback) {
        eventCallback = callback;
        emit("ready", mapOf("message", "levixel event channel ready"));
    }

    @UniJSMethod(uiThread = true)
    public void open(@Nullable Object options, @Nullable UniJSCallback callback) {
        Activity activity = activity();
        if (activity == null) {
            invoke(callback, error("NO_ACTIVITY", "$", "Unable to find the current Activity"));
            return;
        }

        final LevixelUniContract.OpenRequest request;
        try {
            request = LevixelUniContract.parseOpenRequest(options);
        } catch (LevixelUniContract.ContractException exception) {
            invoke(callback, error(exception.code, exception.path, exception.getMessage()));
            return;
        }

        View contentView = activity.findViewById(android.R.id.content);
        View decorView = activity.getWindow() != null ? activity.getWindow().getDecorView() : null;
        if (!(contentView instanceof ViewGroup) || !(decorView instanceof ViewGroup)) {
            invoke(callback, error("NO_HOST", "$", "Unable to find the UniApp window host"));
            return;
        }

        closeActiveSession(false);
        pendingOpenCallback = callback;
        LevixelUniSession session = new LevixelUniSession(
                activity,
                (ViewGroup) decorView,
                LevixelUniViewport.resolve(contentView),
                request,
                this
        );
        activeSession = session;
        session.start();
    }

    @UniJSMethod(uiThread = true)
    public void close(@Nullable Object options, @Nullable UniJSCallback callback) {
        try {
            LevixelUniContract.validateCloseRequest(options);
        } catch (LevixelUniContract.ContractException exception) {
            invoke(callback, error(exception.code, exception.path, exception.getMessage()));
            return;
        }
        closeActiveSession(true);
        invoke(callback, ok(mapOf("closed", true)));
    }

    @Override
    public void onActivityDestroy() {
        closeActiveSession(false);
        eventCallback = null;
        super.onActivityDestroy();
    }

    @Override
    public void onOpened(@NonNull LevixelUniSession session) {
        if (activeSession != session) {
            return;
        }
        if (session.hidesHtmlSource()) {
            emitSourceVisibility(true, session.currentIndex(), session.galleryId());
        }
        Map<String, Object> data = new HashMap<>();
        data.put("index", session.currentIndex());
        data.put("count", session.itemCount());
        data.put("galleryId", session.galleryId());
        invoke(takeOpenCallback(), ok(data));
    }

    @Override
    public void onOpenCancelled(@NonNull LevixelUniSession session) {
        if (activeSession == session) {
            invoke(takeOpenCallback(), error("CANCELLED", "$", "Viewer opening was cancelled"));
        }
    }

    @Override
    public void onIndexChange(
            @NonNull LevixelUniSession session,
            int previousIndex,
            int currentIndex
    ) {
        if (activeSession != session) {
            return;
        }
        if (session.hidesHtmlSource()) {
            emitSourceVisibility(false, previousIndex, session.galleryId());
            emitSourceVisibility(true, currentIndex, session.galleryId());
        }
        emit("indexChange", mapOf("currentIndex", currentIndex));
    }

    @Override
    public void onDismissed(@NonNull LevixelUniSession session, boolean emitDismissEvent) {
        if (activeSession != session) {
            return;
        }
        activeSession = null;
        if (session.hidesHtmlSource()) {
            emitSourceVisibility(false, session.currentIndex(), session.galleryId());
        }
        if (emitDismissEvent) {
            emit("dismiss", new HashMap<>());
        }
    }

    private void closeActiveSession(boolean animated) {
        LevixelUniSession session = activeSession;
        if (session == null) {
            return;
        }
        session.close(animated);
    }

    @Nullable
    private Activity activity() {
        Context context = mUniSDKInstance != null ? mUniSDKInstance.getContext() : null;
        while (context instanceof ContextWrapper) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }

    private void emitSourceVisibility(boolean hidden, int index, @NonNull String galleryId) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("hidden", hidden);
        payload.put("index", index);
        payload.put("galleryId", galleryId);
        emit("sourceVisibilityChange", payload);
    }

    private void emit(@NonNull String type, @NonNull Map<String, Object> payload) {
        UniJSCallback callback = eventCallback;
        if (callback == null) {
            return;
        }
        Map<String, Object> event = new HashMap<>();
        event.put("type", type);
        event.put("payload", payload);
        event.put("time", System.currentTimeMillis());
        callback.invokeAndKeepAlive(event);
    }

    @Nullable
    private UniJSCallback takeOpenCallback() {
        UniJSCallback callback = pendingOpenCallback;
        pendingOpenCallback = null;
        return callback;
    }

    private void invoke(@Nullable UniJSCallback callback, @NonNull Map<String, Object> payload) {
        if (callback != null) {
            callback.invoke(payload);
        }
    }

    @NonNull
    private Map<String, Object> ok(@NonNull Map<String, Object> data) {
        Map<String, Object> result = new HashMap<>();
        result.put("ok", true);
        result.put("data", data);
        return result;
    }

    @NonNull
    private Map<String, Object> error(
            @NonNull String code,
            @NonNull String path,
            @Nullable String message
    ) {
        Map<String, Object> result = new HashMap<>();
        result.put("ok", false);
        result.put("code", code);
        result.put("path", path);
        result.put("message", message == null ? "Levixel request failed" : message);
        return result;
    }

    @NonNull
    private Map<String, Object> mapOf(@NonNull String key, @Nullable Object value) {
        Map<String, Object> result = new HashMap<>();
        result.put(key, value);
        return result;
    }
}
