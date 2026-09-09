package com.sandrox.levixel;

import androidx.annotation.NonNull;

/** Action presentation is explicit and never depends on the action count. */
public enum LevixelActionLayout {
    LIST, GRID;

    @NonNull public static LevixelActionLayout fromValue(@NonNull String value) {
        if ("list".equals(value)) return LIST;
        if ("grid".equals(value)) return GRID;
        throw new IllegalArgumentException("Levixel actionLayout must be list or grid.");
    }
}
