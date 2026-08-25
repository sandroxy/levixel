package com.sandrox.levixel.uniapp.runtime;

import androidx.annotation.NonNull;

import java.util.Map;

@FunctionalInterface
public interface LevixelUniEventListener {
    void onEvent(@NonNull Map<String, Object> event);
}
