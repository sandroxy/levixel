package com.sandrox.levixel.uniapp.runtime;

import androidx.annotation.NonNull;

@FunctionalInterface
public interface LevixelUniJsonCallback {
    void onResult(@NonNull String resultJson);
}
