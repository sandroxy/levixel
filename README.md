# Levixel

Levixel is a shared-transition image and video viewer for native, React Native, UniApp, and browser applications.

The implementation in this directory is the only source of truth. Platform test hosts consume packaged artifacts from `dist/`; they never compile plugin source directly.

## Android

Package the Android AAR:

```sh
./scripts/package-native-android.sh
```

Verify the packaged AAR in the shared Android test host:

```sh
./scripts/verify-native-android.sh
```
