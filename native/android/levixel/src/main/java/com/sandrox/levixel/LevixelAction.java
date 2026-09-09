package com.sandrox.levixel;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;

/** A business-neutral action displayed by the viewer. */
public final class LevixelAction {
    public interface Callback { void onPress(@NonNull LevixelViewerEvent event); }

    @NonNull public final String id;
    @NonNull public final String label;
    @Nullable public final String icon;
    @Nullable public final String group;
    public final boolean disabled;
    public final boolean destructive;
    @Nullable public final Callback onPress;

    public LevixelAction(@NonNull String id, @NonNull String label, @Nullable Callback onPress) {
        this(id, label, null, null, false, false, onPress);
    }

    public LevixelAction(@NonNull String id, @NonNull String label, @Nullable String icon,
            @Nullable String group, boolean disabled, boolean destructive, @Nullable Callback onPress) {
        requireText(id, "id");
        requireText(label, "label");
        if (icon != null) requireText(icon, "icon");
        if (group != null) requireText(group, "group");
        this.id = id;
        this.label = label;
        this.icon = icon;
        this.group = group;
        this.disabled = disabled;
        this.destructive = destructive;
        this.onPress = onPress;
    }

    @NonNull public static List<LevixelAction> snapshot(@NonNull List<LevixelAction> actions) {
        return snapshot(actions, LevixelActionLayout.LIST);
    }

    @NonNull public static List<LevixelAction> snapshot(@NonNull List<LevixelAction> actions, @NonNull LevixelActionLayout layout) {
        if (layout == null) throw new IllegalArgumentException("Levixel actionLayout is required.");
        HashSet<String> ids = new HashSet<>();
        List<LevixelAction> copy = new ArrayList<>(actions.size());
        for (LevixelAction action : actions) {
            if (action == null || !ids.add(action.id)) {
                throw new IllegalArgumentException("Levixel actions require unique IDs and non-null entries.");
            }
            if (layout == LevixelActionLayout.GRID && action.icon == null) {
                throw new IllegalArgumentException("Levixel actions[" + copy.size() + "].icon is required for grid actionLayout.");
            }
            copy.add(action);
        }
        return java.util.Collections.unmodifiableList(copy);
    }

    private static void requireText(String value, String field) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException("Levixel action " + field + " must be non-blank.");
        }
    }
}
