package com.sandrox.levixel.uniapp.runtime;

import androidx.annotation.NonNull;

import java.util.Map;

@FunctionalInterface
public interface LevixelUniResultCallback {
    void onResult(@NonNull Map<String, Object> result);
}
