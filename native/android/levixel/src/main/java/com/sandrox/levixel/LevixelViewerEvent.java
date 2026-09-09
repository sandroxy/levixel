package com.sandrox.levixel;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/** Immutable media identity from one viewer session, including for prefetched pages. */
public final class LevixelViewerEvent {
    @NonNull public final String type;
    @NonNull public final Map<String, Object> payload;
    public final long time;

    LevixelViewerEvent(String type, String sessionId, String galleryId, int index,
            LevixelMediaItem item, @Nullable String actionId) {
        this.type = type;
        this.time = System.currentTimeMillis();
        Map<String, Object> context = new LinkedHashMap<>();
        context.put("sessionId", sessionId);
        context.put("galleryId", galleryId);
        context.put("index", index);
        context.put("itemId", item.getId());
        context.put("mediaType", item.getMediaType() == LevixelMediaItem.MediaType.IMAGE ? "image" : "video");
        if ("indexChange".equals(type)) context.put("currentIndex", index);
        if (actionId != null) context.put("actionId", actionId);
        if ("mediaError".equals(type)) {
            context.put("code", "LOAD_FAILED");
            context.put("message", "Media could not be loaded");
        }
        this.payload = Collections.unmodifiableMap(context);
    }

    @NonNull public Map<String, Object> toMap() {
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("type", type);
        event.put("payload", payload);
        event.put("time", time);
        return event;
    }
}
