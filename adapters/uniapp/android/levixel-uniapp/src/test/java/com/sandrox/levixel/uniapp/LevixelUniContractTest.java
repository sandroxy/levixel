package com.sandrox.levixel.uniapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class LevixelUniContractTest {
    @Test
    public void parsesCanonicalDefaults() throws Exception {
        LevixelUniContract.OpenRequest request = LevixelUniContract.parseOpenRequest(
                openOptions(imageItem())
        );

        assertEquals(1, request.items.size());
        assertEquals(0, request.initialIndex);
        assertFalse(request.lightTheme);
        assertFalse(request.hidesHtmlSource);
    }

    @Test
    public void rejectsUnknownFields() {
        Map<String, Object> options = openOptions(imageItem());
        options.put("urls", Arrays.asList("https://example.com/image.jpg"));

        assertContractError("UNKNOWN_FIELD", "$.urls", options);
    }

    @Test
    public void rejectsExplicitNullInsteadOfTreatingItAsMissing() {
        Map<String, Object> options = openOptions(imageItem());
        options.put("theme", null);

        assertContractError("INVALID_TYPE", "$.theme", options);
    }

    @Test
    public void rejectsExplicitNullItemProperties() {
        Map<String, Object> item = imageItem();
        item.put("thumbnailUrl", null);

        assertContractError("INVALID_TYPE", "$.items[0].thumbnailUrl", openOptions(item));
    }

    @Test
    public void requiresOneSourceHintPerItem() {
        Map<String, Object> options = openOptions(imageItem());
        options.put("sourceHints", new ArrayList<>());

        assertContractError("INVALID_VALUE", "$.sourceHints", options);
    }

    @Test
    public void acceptsNullEntriesInsideSourceHintArray() throws Exception {
        Map<String, Object> options = openOptions(imageItem());
        List<Object> hints = new ArrayList<>();
        hints.add(null);
        options.put("sourceHints", hints);

        LevixelUniContract.OpenRequest request = LevixelUniContract.parseOpenRequest(options);
        assertEquals(1, request.sourceHints.size());
        assertEquals(null, request.sourceHints.get(0));
    }

    @Test
    public void parsesExplicitSourceRectScale() throws Exception {
        Map<String, Object> options = openOptions(imageItem());
        Map<String, Object> rect = new HashMap<>();
        rect.put("left", 12);
        rect.put("top", 24);
        rect.put("width", 100);
        rect.put("height", 80);
        Map<String, Object> hint = new HashMap<>();
        hint.put("rect", rect);
        hint.put("objectFit", "cover");
        hint.put("coordinateSpace", "viewport");
        hint.put("rectScale", 3);
        options.put("sourceHints", Arrays.asList(hint));

        LevixelUniContract.OpenRequest request = LevixelUniContract.parseOpenRequest(options);

        LevixelUniContract.SourceHint parsedHint = request.sourceHints.get(0);
        assertNotNull(parsedHint);
        assertEquals(12d, parsedHint.rect.left, 0d);
        assertEquals(3d, parsedHint.rectScale, 0d);
    }

    @Test
    public void rejectsUnsupportedViewerChrome() {
        Map<String, Object> options = openOptions(imageItem());
        options.put("counter", true);

        assertContractError("UNSUPPORTED_VALUE", "$.counter", options);
    }

    @Test
    public void closeRequestMustBeAnEmptyObject() throws Exception {
        LevixelUniContract.validateCloseRequest(new HashMap<>());

        Map<String, Object> options = new HashMap<>();
        options.put("animated", true);
        try {
            LevixelUniContract.validateCloseRequest(options);
            fail("Expected a contract error");
        } catch (LevixelUniContract.ContractException exception) {
            assertEquals("UNKNOWN_FIELD", exception.code);
            assertEquals("$.animated", exception.path);
        }
    }

    private static Map<String, Object> imageItem() {
        Map<String, Object> item = new HashMap<>();
        item.put("id", "image-1");
        item.put("type", "image");
        item.put("url", "https://example.com/image.jpg");
        return item;
    }

    private static Map<String, Object> openOptions(Map<String, Object> item) {
        Map<String, Object> options = new HashMap<>();
        options.put("items", Arrays.asList(item));
        return options;
    }

    private static void assertContractError(
            String expectedCode,
            String expectedPath,
            Map<String, Object> options
    ) {
        try {
            LevixelUniContract.parseOpenRequest(options);
            fail("Expected a contract error");
        } catch (LevixelUniContract.ContractException exception) {
            assertEquals(expectedCode, exception.code);
            assertEquals(expectedPath, exception.path);
        }
    }
}
