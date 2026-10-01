package com.sandrox.levixel.flutter;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Outline;
import android.graphics.RectF;
import android.os.Build;
import android.view.ContextThemeWrapper;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;
import androidx.appcompat.widget.AppCompatImageView;

import com.sandrox.levixel.LevixelAction;
import com.sandrox.levixel.LevixelActionLayout;
import com.sandrox.levixel.LevixelMediaItem;
import com.sandrox.levixel.LevixelSharedElementNames;
import com.sandrox.levixel.LevixelSourceViewRegistry;
import com.sandrox.levixel.LevixelViewerEvent;
import com.sandrox.levixel.LevixelViewerOverlayView;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Engine-scoped adapter; media, gestures, and transitions belong to the native core. */
public final class LevixelPlugin implements FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private BinaryMessenger messenger;
    private Activity activity;
    private final String engineScope = UUID.randomUUID().toString();
    private Session session;

    @Override public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        messenger = binding.getBinaryMessenger();
        channel = new MethodChannel(messenger, "com.sandrox.levixel/flutter");
        channel.setMethodCallHandler(this);
    }

    @Override public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        detach();
        channel.setMethodCallHandler(null);
        channel = null;
        messenger = null;
    }

    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) { activity = binding.getActivity(); }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) { onAttachedToActivity(binding); }
    @Override public void onDetachedFromActivityForConfigChanges() { detach(); activity = null; }
    @Override public void onDetachedFromActivity() { detach(); activity = null; }

    private void detach() {
        Session old = session;
        session = null;
        if (old != null) {
            if (old.overlay != null) old.overlay.dismissImmediately();
            old.removeSources();
            old.completeClose();
        }
    }

    @Override public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            Map<?, ?> args = map(call.arguments);
            String request = text(args, "requestId");
            if (call.method.equals("prepare")) {
                if (activity == null || activity.isFinishing()) throw new IllegalStateException("No attached Activity");
                if (session != null) throw new IllegalStateException("Close the previous viewer before preparing another");
                Session next = new Session(args);
                session = next;
                try { next.updateSources(list(args, "sources")); }
                catch (RuntimeException error) { next.removeSources(); session = null; throw error; }
                Source selected = next.sources.get(next.sourceId);
                if (selected != null) selected.showPreview(true);
                result.success(null);
                return;
            }
            Session current = session;
            if (current == null || !current.id.equals(request)) {
                if (call.method.equals("open")) result.error("OPEN_CANCELLED", "This request is no longer active", null);
                else result.success(call.method.equals("retry") ? false : null);
                return;
            }
            switch (call.method) {
                case "open": current.open(); result.success(null); break;
                case "updateSources":
                    if (!current.closing) current.updateSources(list(args, "sources"));
                    result.success(null); break;
                case "retry": result.success(current.overlay != null && current.overlay.retry()); break;
                case "close":
                    current.closing = true;
                    if (current.overlay == null) result.success(null);
                    else {
                        boolean animated = bool(args, "animated");
                        current.closeResults.add(result);
                        if (animated) current.overlay.requestClose();
                        else current.overlay.dismissImmediately();
                    }
                    break;
                case "finish":
                    if (current.overlay != null) throw new IllegalStateException("Dismiss the viewer before finishing");
                    current.removeSources(); session = null; result.success(null); break;
                default: result.notImplemented();
            }
        } catch (IllegalArgumentException error) { result.error("INVALID_ARGUMENT", error.getMessage(), null); }
        catch (RuntimeException error) { result.error("OPEN_FAILED", error.getMessage(), null); }
    }

    private final class Session {
        final String id, gallery, scopedGallery, sourceId;
        final int index;
        final boolean light, listIcons;
        final LevixelActionLayout actionLayout;
        final List<LevixelMediaItem> items = new ArrayList<>();
        final List<LevixelAction> actions = new ArrayList<>();
        final Map<String, LevixelMediaItem> byId = new HashMap<>();
        final Map<String, Source> sources = new LinkedHashMap<>();
        final List<MethodChannel.Result> closeResults = new ArrayList<>();
        final ViewGroup host;
        final FlutterView flutterView;
        LevixelViewerOverlayView overlay;
        boolean closing;
        Object backCallback;

        Session(Map<?, ?> args) {
            id = text(args, "requestId"); gallery = text(args, "galleryId");
            scopedGallery = engineScope + ":" + id;
            sourceId = optionalText(args, "sourceId");
            host = (ViewGroup) activity.getWindow().getDecorView();
            flutterView = findFlutterView(host);
            if (flutterView == null) throw new IllegalStateException("The attached Flutter view is unavailable");
            for (Object value : list(args, "items")) {
                Map<?, ?> item = map(value);
                String itemId = text(item, "id"), url = text(item, "url"), type = text(item, "type");
                LevixelMediaItem.MediaType mediaType;
                if (type.equals("image")) mediaType = LevixelMediaItem.MediaType.IMAGE;
                else if (type.equals("video")) mediaType = LevixelMediaItem.MediaType.VIDEO;
                else throw new IllegalArgumentException("Unknown media type");
                String thumbnail = optionalText(item, "thumbnailUrl");
                String poster = optionalText(item, "posterUrl");
                String preview = mediaType == LevixelMediaItem.MediaType.VIDEO && poster != null ? poster : thumbnail;
                LevixelMediaItem media = new LevixelMediaItem(itemId, mediaType, url, preview == null ? url : preview);
                if (byId.put(itemId, media) != null) throw new IllegalArgumentException("Media IDs must be unique");
                items.add(media);
            }
            index = integer(args, "index");
            if (items.isEmpty() || index < 0 || index >= items.size()) throw new IllegalArgumentException("Invalid media index");
            String theme = text(args, "theme");
            if (!theme.equals("light") && !theme.equals("dark")) throw new IllegalArgumentException("Invalid theme");
            light = theme.equals("light");
            actionLayout = LevixelActionLayout.fromValue(text(args, "actionLayout"));
            listIcons = bool(args, "actionListIcons");
            for (Object value : list(args, "actions")) {
                Map<?, ?> action = map(value);
                actions.add(new LevixelAction(text(action, "id"), text(action, "label"), optionalText(action, "icon"),
                        optionalText(action, "group"), bool(action, "disabled"), bool(action, "destructive"), null));
            }
            LevixelAction.snapshot(actions, actionLayout);
        }

        void open() {
            if (closing || overlay != null || !flutterView.isAttachedToWindow()) throw new IllegalStateException("The viewer cannot be opened");
            Context context = new ContextThemeWrapper(activity, com.google.android.material.R.style.Theme_MaterialComponents_DayNight_NoActionBar);
            overlay = new LevixelViewerOverlayView(context, items, null, index, light, scopedGallery, actions, actionLayout, listIcons,
                    sourceId, new LevixelViewerOverlayView.Listener() {
                @Override public void onOverlayIndexChange(int value) { }
                @Override public void onViewerEvent(@NonNull LevixelViewerEvent event) {
                    Map<String, Object> value = new HashMap<>(event.toMap());
                    Map<String, Object> payload = new HashMap<>(event.payload);
                    payload.put("galleryId", gallery);
                    value.put("payload", payload); value.put("requestId", id);
                    if (channel != null) channel.invokeMethod("event", value);
                }
                @Override public void onOverlayDismissed() {
                    if (Build.VERSION.SDK_INT >= 33 && backCallback != null) Api33.unregister(host, backCallback);
                    backCallback = null; overlay = null; closing = true; completeClose();
                }
            });
            host.addView(overlay);
            overlay.requestFocus();
            if (Build.VERSION.SDK_INT >= 33) backCallback = Api33.register(host, () -> { if (overlay != null) overlay.handleBack(); });
        }

        void updateSources(List<?> values) {
            HashSet<String> retained = new HashSet<>();
            for (Object value : values) {
                Map<?, ?> source = map(value);
                String sourceId = text(source, "sourceId"), itemId = text(source, "itemId");
                if (!byId.containsKey(itemId) || !retained.add(sourceId)) throw new IllegalArgumentException("Invalid source identity");
                Source anchor = sources.get(sourceId);
                if (anchor != null && !anchor.itemId.equals(itemId)) { anchor.remove(); sources.remove(sourceId); anchor = null; }
                if (anchor == null) {
                    anchor = new Source(this, sourceId, itemId);
                    sources.put(sourceId, anchor); host.addView(anchor);
                    if (overlay != null) overlay.bringToFront();
                }
                anchor.update(source);
            }
            for (String sourceId : new ArrayList<>(sources.keySet())) {
                if (!retained.contains(sourceId)) sources.remove(sourceId).remove();
            }
        }

        void removeSources() { for (Source source : sources.values()) source.remove(); sources.clear(); }
        void completeClose() {
            List<MethodChannel.Result> pending = new ArrayList<>(closeResults); closeResults.clear();
            for (MethodChannel.Result result : pending) result.success(null);
        }
    }

    private final class Source extends FrameLayout {
        final Session owner;
        final String id, itemId, key;
        final ImageView image;
        boolean preview, ready;
        float radius;
        int visibilitySequence;

        Source(Session owner, String id, String itemId) {
            super(new ContextThemeWrapper(activity, com.google.android.material.R.style.Theme_MaterialComponents_DayNight_NoActionBar));
            this.owner = owner; this.id = id; this.itemId = itemId;
            key = LevixelSharedElementNames.forItem(owner.scopedGallery, owner.byId.get(itemId));
            setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
            setClipChildren(true); setClipToOutline(true);
            setOutlineProvider(new ViewOutlineProvider() {
                @Override public void getOutline(View view, Outline outline) { outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius); }
            });
            image = new AppCompatImageView(getContext()) {
                @Override protected void onDraw(Canvas canvas) { if (preview) super.onDraw(canvas); }
            };
            addView(image); ready = true;
        }

        void update(Map<?, ?> args) {
            float scale = number(args.get("pixelRatio"));
            if (scale <= 0) throw new IllegalArgumentException("Invalid pixel ratio");
            RectF frame = rect(args.get("frame"), scale), clip = rect(args.get("clip"), scale);
            int[] flutterOrigin = new int[2], hostOrigin = new int[2];
            owner.flutterView.getLocationOnScreen(flutterOrigin); owner.host.getLocationOnScreen(hostOrigin);
            setLayoutParams(new FrameLayout.LayoutParams((int) Math.ceil(clip.width()), (int) Math.ceil(clip.height())));
            setX(clip.left + flutterOrigin[0] - hostOrigin[0]); setY(clip.top + flutterOrigin[1] - hostOrigin[1]);
            image.setLayoutParams(new FrameLayout.LayoutParams((int) Math.ceil(frame.width()), (int) Math.ceil(frame.height())));
            image.setX(frame.left - clip.left); image.setY(frame.top - clip.top);
            radius = frame.equals(clip) ? number(args.get("cornerRadius")) * scale : 0;
            if (radius < 0) throw new IllegalArgumentException("Invalid corner radius");
            invalidateOutline();
            String fit = text(args, "fit");
            if (fit.equals("cover")) image.setScaleType(ImageView.ScaleType.CENTER_CROP);
            else if (fit.equals("contain")) image.setScaleType(ImageView.ScaleType.FIT_CENTER);
            else if (fit.equals("fill")) image.setScaleType(ImageView.ScaleType.FIT_XY);
            else throw new IllegalArgumentException("Invalid source fit");
            if (args.get("png") != null) {
                if (!(args.get("png") instanceof byte[])) throw new IllegalArgumentException("Invalid source image");
                byte[] bytes = (byte[]) args.get("png");
                BitmapFactory.Options bounds = new BitmapFactory.Options(); bounds.inJustDecodeBounds = true;
                BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
                if (bounds.outWidth < 1 || bounds.outHeight < 1 || bounds.outWidth > 1024 || bounds.outHeight > 1024) throw new IllegalArgumentException("Invalid source image size");
                Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                if (bitmap == null) throw new IllegalArgumentException("Invalid source image");
                image.setImageBitmap(bitmap);
            }
            LevixelSourceViewRegistry.registerSource(key, image, number(args.get("cornerRadius")) * scale, this, id);
        }

        void showPreview(boolean value) { preview = value; image.invalidate(); }

        @Override public void setAlpha(float alpha) {
            float previous = getAlpha(); super.setAlpha(alpha);
            if (!ready || previous == alpha) return;
            boolean hidden = alpha == 0;
            showPreview(!hidden);
            int sequence = ++visibilitySequence;
            Map<String, Object> value = new HashMap<>();
            value.put("requestId", owner.id); value.put("sourceId", id); value.put("hidden", hidden);
            if (channel != null) channel.invokeMethod("visibility", value, new MethodChannel.Result() {
                @Override public void success(Object ignored) {
                    postOnAnimation(() -> { if (visibilitySequence == sequence && !hidden) showPreview(false); });
                }
                @Override public void error(String code, String message, Object details) { success(null); }
                @Override public void notImplemented() { success(null); }
            });
        }

        void remove() {
            LevixelSourceViewRegistry.unregisterSource(this);
            if (getParent() instanceof ViewGroup) ((ViewGroup) getParent()).removeView(this);
            image.setImageDrawable(null);
        }
    }

    private FlutterView findFlutterView(View view) {
        if (view instanceof FlutterView) {
            BinaryMessenger candidate = ((FlutterView) view).getBinaryMessenger();
            if (candidate == messenger || (candidate instanceof DartExecutor
                    && ((DartExecutor) candidate).getBinaryMessenger() == messenger)) return (FlutterView) view;
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) { FlutterView found = findFlutterView(group.getChildAt(i)); if (found != null) return found; }
        }
        return null;
    }

    @RequiresApi(33)
    private static final class Api33 {
        static Object register(View host, Runnable action) {
            OnBackInvokedDispatcher dispatcher = host.findOnBackInvokedDispatcher();
            if (dispatcher == null) return null;
            OnBackInvokedCallback callback = action::run;
            dispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_OVERLAY, callback);
            return callback;
        }
        static void unregister(View host, Object callback) {
            OnBackInvokedDispatcher dispatcher = host.findOnBackInvokedDispatcher();
            if (dispatcher != null) dispatcher.unregisterOnBackInvokedCallback((OnBackInvokedCallback) callback);
        }
    }

    private static Map<?, ?> map(Object value) { if (!(value instanceof Map)) throw new IllegalArgumentException("Expected an object"); return (Map<?, ?>) value; }
    private static List<?> list(Map<?, ?> value, String key) { if (!(value.get(key) instanceof List)) throw new IllegalArgumentException("Expected " + key); return (List<?>) value.get(key); }
    private static String text(Map<?, ?> value, String key) {
        Object field = value.get(key);
        if (!(field instanceof String) || ((String) field).trim().isEmpty()) throw new IllegalArgumentException("Invalid " + key);
        return (String) field;
    }
    private static String optionalText(Map<?, ?> value, String key) { return value.get(key) == null ? null : text(value, key); }
    private static boolean bool(Map<?, ?> value, String key) { if (!(value.get(key) instanceof Boolean)) throw new IllegalArgumentException("Invalid " + key); return (Boolean) value.get(key); }
    private static float number(Object value) { if (!(value instanceof Number) || !Float.isFinite(((Number) value).floatValue())) throw new IllegalArgumentException("Expected a finite number"); return ((Number) value).floatValue(); }
    private static int integer(Map<?, ?> value, String key) { float n = number(value.get(key)); if (n != (int) n) throw new IllegalArgumentException("Invalid " + key); return (int) n; }
    private static RectF rect(Object value, float scale) {
        if (!(value instanceof List) || ((List<?>) value).size() != 4) throw new IllegalArgumentException("Invalid source rectangle");
        List<?> v = (List<?>) value;
        float x = number(v.get(0)) * scale, y = number(v.get(1)) * scale, width = number(v.get(2)) * scale, height = number(v.get(3)) * scale;
        if (width <= 0 || height <= 0) throw new IllegalArgumentException("Empty source rectangle");
        return new RectF(x, y, x + width, y + height);
    }
}
