package com.sandrox.levixel.uniapp.runtime;

import androidx.annotation.NonNull;

@FunctionalInterface
public interface LevixelUniJsonEventListener {
    void onEvent(@NonNull String eventJson);
}
