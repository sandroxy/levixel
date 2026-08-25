package com.sandrox.levixel.uniapp;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.sandrox.levixel.uniapp.runtime.LevixelUniEventListener;
import com.sandrox.levixel.uniapp.runtime.LevixelUniRuntime;

import java.util.Map;

import io.dcloud.feature.uniapp.annotation.UniJSMethod;
import io.dcloud.feature.uniapp.bridge.UniJSCallback;
import io.dcloud.feature.uniapp.common.UniModule;

public final class LevixelUniModule extends UniModule {
    @NonNull private final LevixelUniRuntime runtime = LevixelUniRuntime.getShared();
    @NonNull private final LevixelUniEventListener runtimeEventListener = this::emit;

    @Nullable private UniJSCallback eventCallback;

    @UniJSMethod(uiThread = true)
    public void onEvent(@Nullable UniJSCallback callback) {
        eventCallback = callback;
        runtime.setEventListener(callback == null ? null : runtimeEventListener);
    }

    @UniJSMethod(uiThread = true)
    public void open(@Nullable Object options, @Nullable UniJSCallback callback) {
        Activity activity = activity();
        if (activity == null) {
            invoke(callback, noActivityError());
            return;
        }
        runtime.open(activity, options, result -> invoke(callback, result));
    }

    @UniJSMethod(uiThread = true)
    public void close(@Nullable Object options, @Nullable UniJSCallback callback) {
        runtime.close(options, result -> invoke(callback, result));
    }

    @Override
    public void onActivityDestroy() {
        runtime.closeImmediately();
        runtime.setEventListener(null);
        eventCallback = null;
        super.onActivityDestroy();
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

    private void emit(@NonNull Map<String, Object> event) {
        UniJSCallback callback = eventCallback;
        if (callback != null) {
            callback.invokeAndKeepAlive(event);
        }
    }

    private void invoke(@Nullable UniJSCallback callback, @NonNull Map<String, Object> result) {
        if (callback != null) {
            callback.invoke(result);
        }
    }

    @NonNull
    private Map<String, Object> noActivityError() {
        Map<String, Object> result = new java.util.HashMap<>();
        result.put("ok", false);
        result.put("code", "NO_ACTIVITY");
        result.put("path", "$");
        result.put("message", "Unable to find the current Activity");
        return result;
    }
}
