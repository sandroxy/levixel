package com.sandrox.levixel.uniapp.runtime;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

public final class LevixelUniRuntime implements LevixelUniSession.Listener {
    @NonNull private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Nullable private LevixelUniSession activeSession;
    @Nullable private LevixelUniResultCallback pendingOpenCallback;
    @Nullable private LevixelUniEventListener eventListener;
    @Nullable private LevixelUniJsonEventListener jsonEventListener;

    private LevixelUniRuntime() {
    }

    @NonNull
    public static LevixelUniRuntime getShared() {
        return SharedHolder.INSTANCE;
    }

    public void setEventListener(@Nullable LevixelUniEventListener listener) {
        eventListener = listener;
        if (listener != null) {
            listener.onEvent(event("ready", mapOf("message", "levixel event channel ready")));
        }
    }

    public void setJsonEventListener(@Nullable LevixelUniJsonEventListener listener) {
        jsonEventListener = listener;
        if (listener != null) {
            listener.onEvent(toJson(event(
                    "ready",
                    mapOf("message", "levixel event channel ready")
            )));
        }
    }

    public void open(
            @NonNull Activity activity,
            @Nullable Object options,
            @Nullable LevixelUniResultCallback callback
    ) {
        runOnMain(() -> openOnMain(activity, options, callback));
    }

    public void openJson(
            @NonNull Activity activity,
            @NonNull String optionsJson,
            @Nullable LevixelUniJsonCallback callback
    ) {
        runOnMain(() -> {
            final Map<String, Object> options;
            try {
                options = parseJsonObject(optionsJson);
            } catch (JSONException exception) {
                invoke(callback, errorJson(
                        "INVALID_JSON",
                        "$",
                        "Request must be a valid JSON object"
                ));
                return;
            }
            openOnMain(activity, options, result -> invoke(callback, toJson(result)));
        });
    }

    public void close(
            @Nullable Object options,
            @Nullable LevixelUniResultCallback callback
    ) {
        runOnMain(() -> closeOnMain(options, callback));
    }

    public void closeJson(
            @NonNull String optionsJson,
            @Nullable LevixelUniJsonCallback callback
    ) {
        runOnMain(() -> {
            final Map<String, Object> options;
            try {
                options = parseJsonObject(optionsJson);
            } catch (JSONException exception) {
                invoke(callback, errorJson(
                        "INVALID_JSON",
                        "$",
                        "Request must be a valid JSON object"
                ));
                return;
            }
            closeOnMain(options, result -> invoke(callback, toJson(result)));
        });
    }

    public void closeImmediately() {
        runOnMain(() -> closeActiveSession(false));
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

    private void openOnMain(
            @NonNull Activity activity,
            @Nullable Object options,
            @Nullable LevixelUniResultCallback callback
    ) {
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

    private void closeOnMain(
            @Nullable Object options,
            @Nullable LevixelUniResultCallback callback
    ) {
        try {
            LevixelUniContract.validateCloseRequest(options);
        } catch (LevixelUniContract.ContractException exception) {
            invoke(callback, error(exception.code, exception.path, exception.getMessage()));
            return;
        }
        closeActiveSession(true);
        invoke(callback, ok(mapOf("closed", true)));
    }

    private void closeActiveSession(boolean animated) {
        LevixelUniSession session = activeSession;
        if (session != null) {
            session.close(animated);
        }
    }

    private void emitSourceVisibility(boolean hidden, int index, @NonNull String galleryId) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("hidden", hidden);
        payload.put("index", index);
        payload.put("galleryId", galleryId);
        emit("sourceVisibilityChange", payload);
    }

    private void emit(@NonNull String type, @NonNull Map<String, Object> payload) {
        Map<String, Object> event = event(type, payload);
        LevixelUniEventListener listener = eventListener;
        if (listener != null) {
            listener.onEvent(event);
        }
        LevixelUniJsonEventListener jsonListener = jsonEventListener;
        if (jsonListener != null) {
            jsonListener.onEvent(toJson(event));
        }
    }

    @NonNull
    private Map<String, Object> event(
            @NonNull String type,
            @NonNull Map<String, Object> payload
    ) {
        Map<String, Object> event = new HashMap<>();
        event.put("type", type);
        event.put("payload", payload);
        event.put("time", System.currentTimeMillis());
        return event;
    }

    @Nullable
    private LevixelUniResultCallback takeOpenCallback() {
        LevixelUniResultCallback callback = pendingOpenCallback;
        pendingOpenCallback = null;
        return callback;
    }

    private void runOnMain(@NonNull Runnable action) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action.run();
        } else {
            mainHandler.post(action);
        }
    }

    private static void invoke(
            @Nullable LevixelUniResultCallback callback,
            @NonNull Map<String, Object> result
    ) {
        if (callback != null) {
            callback.onResult(result);
        }
    }

    private static void invoke(
            @Nullable LevixelUniJsonCallback callback,
            @NonNull String resultJson
    ) {
        if (callback != null) {
            callback.onResult(resultJson);
        }
    }

    @NonNull
    private static Map<String, Object> ok(@NonNull Map<String, Object> data) {
        Map<String, Object> result = new HashMap<>();
        result.put("ok", true);
        result.put("data", data);
        return result;
    }

    @NonNull
    private static Map<String, Object> error(
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
    private static String errorJson(
            @NonNull String code,
            @NonNull String path,
            @NonNull String message
    ) {
        return toJson(error(code, path, message));
    }

    @NonNull
    private static Map<String, Object> mapOf(@NonNull String key, @Nullable Object value) {
        Map<String, Object> result = new HashMap<>();
        result.put(key, value);
        return result;
    }

    @NonNull
    private static String toJson(@NonNull Map<String, Object> value) {
        return new JSONObject(value).toString();
    }

    @NonNull
    static Map<String, Object> parseJsonObject(@NonNull String json) throws JSONException {
        return jsonObjectToMap(new JSONObject(json));
    }

    @NonNull
    private static Map<String, Object> jsonObjectToMap(@NonNull JSONObject object)
            throws JSONException {
        Map<String, Object> result = new HashMap<>();
        Iterator<String> keys = object.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            result.put(key, jsonValueToJava(object.get(key)));
        }
        return result;
    }

    @NonNull
    private static List<Object> jsonArrayToList(@NonNull JSONArray array) throws JSONException {
        List<Object> result = new ArrayList<>(array.length());
        for (int index = 0; index < array.length(); index++) {
            result.add(jsonValueToJava(array.get(index)));
        }
        return result;
    }

    @Nullable
    private static Object jsonValueToJava(@NonNull Object value) throws JSONException {
        if (value == JSONObject.NULL) {
            return null;
        }
        if (value instanceof JSONObject) {
            return jsonObjectToMap((JSONObject) value);
        }
        if (value instanceof JSONArray) {
            return jsonArrayToList((JSONArray) value);
        }
        return value;
    }

    private static final class SharedHolder {
        @NonNull static final LevixelUniRuntime INSTANCE = new LevixelUniRuntime();
    }
}
