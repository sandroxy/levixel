package com.sandrox.levixel.uniapp.runtime;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

import java.util.List;
import java.util.Map;

public final class LevixelUniRuntimeJsonTest {
    @Test
    public void parsesUtsJsonBoundaryIntoCanonicalContractValues() throws Exception {
        Map<String, Object> options = LevixelUniRuntime.parseJsonObject(
                "{\"items\":[{\"id\":\"image-1\",\"type\":\"image\","
                        + "\"url\":\"https://example.com/image.jpg\"}],"
                        + "\"sourceHints\":[null],\"sourceVisibility\":\"visible\"}"
        );

        LevixelUniContract.OpenRequest request = LevixelUniContract.parseOpenRequest(options);

        assertEquals(1, request.items.size());
        assertEquals(1, request.sourceHints.size());
        assertNull(request.sourceHints.get(0));
    }

    @Test
    @SuppressWarnings("unchecked")
    public void preservesExplicitNullObjectPropertiesForContractRejection() throws Exception {
        Map<String, Object> options = LevixelUniRuntime.parseJsonObject(
                "{\"items\":[{\"id\":\"image-1\",\"type\":\"image\","
                        + "\"url\":\"https://example.com/image.jpg\",\"thumbnailUrl\":null}]}"
        );

        Map<String, Object> item = (Map<String, Object>) ((List<?>) options.get("items")).get(0);
        assertNull(item.get("thumbnailUrl"));
    }
}
