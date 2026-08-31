package com.sandrox.levixel.uniapp.runtime;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.sandrox.levixel.LevixelMediaItem;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class LevixelUniContract {
    private static final Set<String> OPEN_KEYS = keys(
            "items",
            "index",
            "theme",
            "sourceHints",
            "sourceVisibility",
            "counter",
            "closeButton"
    );
    private static final Set<String> ITEM_KEYS = keys(
            "id",
            "type",
            "url",
            "thumbnailUrl",
            "posterUrl",
            "width",
            "height",
            "alt"
    );
    private static final Set<String> SOURCE_HINT_KEYS = keys(
            "rect",
            "imageSize",
            "objectFit",
            "coordinateSpace",
            "rectScale",
            "cornerRadius"
    );
    private static final Set<String> RECT_KEYS = keys("left", "top", "width", "height");
    private static final Set<String> SIZE_KEYS = keys("width", "height");

    private LevixelUniContract() {
    }

    @NonNull
    static OpenRequest parseOpenRequest(@Nullable Object rawOptions) throws ContractException {
        Map<String, Object> options = requireObject(rawOptions, "$");
        rejectUnknownKeys(options, OPEN_KEYS, "$");

        Object rawItems = options.get("items");
        if (!(rawItems instanceof List)) {
            throw error("INVALID_TYPE", "$.items", "must be an array");
        }

        List<?> itemValues = (List<?>) rawItems;
        if (itemValues.isEmpty()) {
            throw error("INVALID_VALUE", "$.items", "must contain at least one item");
        }

        List<Item> items = new ArrayList<>(itemValues.size());
        Set<String> itemIds = new HashSet<>();
        for (int index = 0; index < itemValues.size(); index++) {
            Item item = parseItem(itemValues.get(index), "$.items[" + index + "]");
            if (!itemIds.add(item.id)) {
                throw error(
                        "INVALID_VALUE",
                        "$.items[" + index + "].id",
                        "must be unique within $.items"
                );
            }
            items.add(item);
        }

        int initialIndex = optionalInteger(options.get("index"), 0, "$.index");
        if (initialIndex < 0 || initialIndex >= items.size()) {
            throw error("OUT_OF_RANGE", "$.index", "must reference an item in $.items");
        }

        String theme = optionalEnum(options.get("theme"), "dark", "$.theme", "dark", "light");
        String sourceVisibility = optionalEnum(
                options.get("sourceVisibility"),
                "visible",
                "$.sourceVisibility",
                "hidden",
                "visible"
        );
        boolean counter = optionalBoolean(options.get("counter"), false, "$.counter");
        boolean closeButton = optionalBoolean(options.get("closeButton"), false, "$.closeButton");
        if (counter) {
            throw error("UNSUPPORTED_VALUE", "$.counter", "Levixel does not render a counter overlay");
        }
        if (closeButton) {
            throw error("UNSUPPORTED_VALUE", "$.closeButton", "Levixel closes by gesture, tap, or back action");
        }

        List<SourceHint> sourceHints = parseSourceHints(options.get("sourceHints"), items.size());
        return new OpenRequest(
                items,
                sourceHints,
                initialIndex,
                "light".equals(theme),
                "hidden".equals(sourceVisibility)
        );
    }

    static void validateCloseRequest(@Nullable Object rawOptions) throws ContractException {
        Map<String, Object> options = requireObject(rawOptions, "$");
        rejectUnknownKeys(options, Collections.emptySet(), "$");
    }

    @NonNull
    private static Item parseItem(@Nullable Object rawItem, @NonNull String path) throws ContractException {
        Map<String, Object> item = requireObject(rawItem, path);
        rejectUnknownKeys(item, ITEM_KEYS, path);

        String id = requireString(item.get("id"), path + ".id");
        String type = requireEnum(item.get("type"), path + ".type", "image", "video");
        String url = requireString(item.get("url"), path + ".url");
        String thumbnailUrl = optionalString(item.get("thumbnailUrl"), path + ".thumbnailUrl");
        String posterUrl = optionalString(item.get("posterUrl"), path + ".posterUrl");
        Double width = optionalPositiveNumber(item.get("width"), path + ".width");
        Double height = optionalPositiveNumber(item.get("height"), path + ".height");
        String alt = optionalString(item.get("alt"), path + ".alt");

        return new Item(id, type, url, thumbnailUrl, posterUrl, width, height, alt);
    }

    @NonNull
    private static List<SourceHint> parseSourceHints(@Nullable Object rawHints, int itemCount)
            throws ContractException {
        List<SourceHint> hints = new ArrayList<>(Collections.nCopies(itemCount, null));
        if (rawHints == null) {
            return hints;
        }
        if (!(rawHints instanceof List)) {
            throw error("INVALID_TYPE", "$.sourceHints", "must be an array");
        }

        List<?> values = (List<?>) rawHints;
        if (values.size() != itemCount) {
            throw error("INVALID_VALUE", "$.sourceHints", "must contain one entry for each media item");
        }
        for (int index = 0; index < values.size(); index++) {
            Object value = values.get(index);
            if (value != null) {
                hints.set(index, parseSourceHint(value, "$.sourceHints[" + index + "]"));
            }
        }
        return hints;
    }

    @NonNull
    private static SourceHint parseSourceHint(@NonNull Object rawHint, @NonNull String path)
            throws ContractException {
        Map<String, Object> hint = requireObject(rawHint, path);
        rejectUnknownKeys(hint, SOURCE_HINT_KEYS, path);

        Map<String, Object> rectValue = requireObject(hint.get("rect"), path + ".rect");
        rejectUnknownKeys(rectValue, RECT_KEYS, path + ".rect");
        SourceRect rect = new SourceRect(
                requireFiniteNumber(rectValue.get("left"), path + ".rect.left"),
                requireFiniteNumber(rectValue.get("top"), path + ".rect.top"),
                requirePositiveNumber(rectValue.get("width"), path + ".rect.width"),
                requirePositiveNumber(rectValue.get("height"), path + ".rect.height")
        );

        ImageSize imageSize = null;
        if (hint.get("imageSize") != null) {
            Map<String, Object> sizeValue = requireObject(hint.get("imageSize"), path + ".imageSize");
            rejectUnknownKeys(sizeValue, SIZE_KEYS, path + ".imageSize");
            imageSize = new ImageSize(
                    requirePositiveNumber(sizeValue.get("width"), path + ".imageSize.width"),
                    requirePositiveNumber(sizeValue.get("height"), path + ".imageSize.height")
            );
        }

        String objectFit = requireEnum(
                hint.get("objectFit"),
                path + ".objectFit",
                "contain",
                "cover",
                "fill"
        );
        String coordinateSpace = requireEnum(
                hint.get("coordinateSpace"),
                path + ".coordinateSpace",
                "screen",
                "viewport"
        );
        Double rectScale = optionalPositiveNumber(hint.get("rectScale"), path + ".rectScale");
        double cornerRadius = optionalNonNegativeNumber(
                hint.get("cornerRadius"),
                0,
                path + ".cornerRadius"
        );
        return new SourceHint(rect, imageSize, objectFit, coordinateSpace, rectScale, cornerRadius);
    }

    @SuppressWarnings("unchecked")
    @NonNull
    private static Map<String, Object> requireObject(@Nullable Object value, @NonNull String path)
            throws ContractException {
        if (!(value instanceof Map)) {
            throw error("INVALID_TYPE", path, "must be an object");
        }
        Map<?, ?> rawMap = (Map<?, ?>) value;
        for (Map.Entry<?, ?> entry : rawMap.entrySet()) {
            Object key = entry.getKey();
            if (!(key instanceof String)) {
                throw error("INVALID_TYPE", path, "must use string property names");
            }
            if (entry.getValue() == null) {
                throw error("INVALID_TYPE", path + "." + key, "must not be null");
            }
        }
        return (Map<String, Object>) value;
    }

    private static void rejectUnknownKeys(
            @NonNull Map<String, Object> value,
            @NonNull Set<String> allowed,
            @NonNull String path
    ) throws ContractException {
        for (String key : value.keySet()) {
            if (!allowed.contains(key)) {
                throw error("UNKNOWN_FIELD", path + "." + key, "is not part of the Levixel contract");
            }
        }
    }

    @NonNull
    private static String requireString(@Nullable Object value, @NonNull String path) throws ContractException {
        if (!(value instanceof String) || ((String) value).isEmpty()) {
            throw error("INVALID_TYPE", path, "must be a non-empty string");
        }
        return (String) value;
    }

    @Nullable
    private static String optionalString(@Nullable Object value, @NonNull String path) throws ContractException {
        if (value == null) {
            return null;
        }
        return requireString(value, path);
    }

    @NonNull
    private static String requireEnum(@Nullable Object value, @NonNull String path, @NonNull String... values)
            throws ContractException {
        String string = requireString(value, path);
        for (String candidate : values) {
            if (candidate.equals(string)) {
                return string;
            }
        }
        throw error("UNKNOWN_ENUM", path, "contains an unsupported value");
    }

    @NonNull
    private static String optionalEnum(
            @Nullable Object value,
            @NonNull String fallback,
            @NonNull String path,
            @NonNull String... values
    ) throws ContractException {
        return value == null ? fallback : requireEnum(value, path, values);
    }

    private static int optionalInteger(@Nullable Object value, int fallback, @NonNull String path)
            throws ContractException {
        if (value == null) {
            return fallback;
        }
        double number = requireFiniteNumber(value, path);
        if (number != Math.rint(number) || number < Integer.MIN_VALUE || number > Integer.MAX_VALUE) {
            throw error("INVALID_TYPE", path, "must be an integer");
        }
        return (int) number;
    }

    private static boolean optionalBoolean(@Nullable Object value, boolean fallback, @NonNull String path)
            throws ContractException {
        if (value == null) {
            return fallback;
        }
        if (!(value instanceof Boolean)) {
            throw error("INVALID_TYPE", path, "must be a boolean");
        }
        return (Boolean) value;
    }

    private static double requireFiniteNumber(@Nullable Object value, @NonNull String path)
            throws ContractException {
        if (!(value instanceof Number)) {
            throw error("INVALID_TYPE", path, "must be a number");
        }
        double number = ((Number) value).doubleValue();
        if (!Double.isFinite(number)) {
            throw error("INVALID_VALUE", path, "must be finite");
        }
        return number;
    }

    private static double requirePositiveNumber(@Nullable Object value, @NonNull String path)
            throws ContractException {
        double number = requireFiniteNumber(value, path);
        if (number <= 0) {
            throw error("OUT_OF_RANGE", path, "must be greater than zero");
        }
        return number;
    }

    @Nullable
    private static Double optionalPositiveNumber(@Nullable Object value, @NonNull String path)
            throws ContractException {
        return value == null ? null : requirePositiveNumber(value, path);
    }

    private static double optionalNonNegativeNumber(
            @Nullable Object value,
            double fallback,
            @NonNull String path
    ) throws ContractException {
        if (value == null) {
            return fallback;
        }
        double number = requireFiniteNumber(value, path);
        if (number < 0) {
            throw error("OUT_OF_RANGE", path, "must be zero or greater");
        }
        return number;
    }

    @NonNull
    private static Set<String> keys(@NonNull String... values) {
        return Collections.unmodifiableSet(new HashSet<>(Arrays.asList(values)));
    }

    @NonNull
    private static ContractException error(
            @NonNull String code,
            @NonNull String path,
            @NonNull String message
    ) {
        return new ContractException(code, path, message);
    }

    static final class OpenRequest {
        @NonNull final List<Item> items;
        @NonNull final List<SourceHint> sourceHints;
        final int initialIndex;
        final boolean lightTheme;
        final boolean hidesHtmlSource;

        OpenRequest(
                @NonNull List<Item> items,
                @NonNull List<SourceHint> sourceHints,
                int initialIndex,
                boolean lightTheme,
                boolean hidesHtmlSource
        ) {
            this.items = items;
            this.sourceHints = sourceHints;
            this.initialIndex = initialIndex;
            this.lightTheme = lightTheme;
            this.hidesHtmlSource = hidesHtmlSource;
        }

        @NonNull
        List<LevixelMediaItem> nativeItems() {
            List<LevixelMediaItem> result = new ArrayList<>(items.size());
            for (Item item : items) {
                result.add(new LevixelMediaItem(
                        item.id,
                        item.isVideo() ? LevixelMediaItem.MediaType.VIDEO : LevixelMediaItem.MediaType.IMAGE,
                        item.url,
                        item.transitionUrl()
                ));
            }
            return result;
        }
    }

    static final class Item {
        @NonNull final String id;
        @NonNull final String type;
        @NonNull final String url;
        @Nullable final String thumbnailUrl;
        @Nullable final String posterUrl;
        @Nullable final Double width;
        @Nullable final Double height;
        @Nullable final String alt;

        Item(
                @NonNull String id,
                @NonNull String type,
                @NonNull String url,
                @Nullable String thumbnailUrl,
                @Nullable String posterUrl,
                @Nullable Double width,
                @Nullable Double height,
                @Nullable String alt
        ) {
            this.id = id;
            this.type = type;
            this.url = url;
            this.thumbnailUrl = thumbnailUrl;
            this.posterUrl = posterUrl;
            this.width = width;
            this.height = height;
            this.alt = alt;
        }

        boolean isVideo() {
            return "video".equals(type);
        }

        @Nullable
        String transitionUrl() {
            if (isVideo()) {
                return posterUrl != null ? posterUrl : thumbnailUrl;
            }
            return thumbnailUrl != null ? thumbnailUrl : url;
        }
    }

    static final class SourceHint {
        @NonNull final SourceRect rect;
        @Nullable final ImageSize imageSize;
        @NonNull final String objectFit;
        @NonNull final String coordinateSpace;
        @Nullable final Double rectScale;
        final double cornerRadius;

        SourceHint(
                @NonNull SourceRect rect,
                @Nullable ImageSize imageSize,
                @NonNull String objectFit,
                @NonNull String coordinateSpace,
                @Nullable Double rectScale,
                double cornerRadius
        ) {
            this.rect = rect;
            this.imageSize = imageSize;
            this.objectFit = objectFit;
            this.coordinateSpace = coordinateSpace;
            this.rectScale = rectScale;
            this.cornerRadius = cornerRadius;
        }
    }

    static final class SourceRect {
        final double left;
        final double top;
        final double width;
        final double height;

        SourceRect(double left, double top, double width, double height) {
            this.left = left;
            this.top = top;
            this.width = width;
            this.height = height;
        }
    }

    static final class ImageSize {
        final double width;
        final double height;

        ImageSize(double width, double height) {
            this.width = width;
            this.height = height;
        }
    }

    static final class ContractException extends Exception {
        @NonNull final String code;
        @NonNull final String path;

        ContractException(@NonNull String code, @NonNull String path, @NonNull String message) {
            super(path + " " + message);
            this.code = code;
            this.path = path;
        }
    }
}
