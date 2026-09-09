package com.sandrox.levixel;

import org.junit.Test;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import static org.junit.Assert.*;

public final class LevixelActionTest {
    @Test public void layoutDoesNotDependOnCountAndGridRequiresIcons() {
        List<LevixelAction> actions = new ArrayList<>();
        for (int index = 0; index < 10; index++) actions.add(new LevixelAction("a" + index, "Action " + index, null));
        assertEquals(10, LevixelAction.snapshot(actions, LevixelActionLayout.LIST).size());
        IllegalArgumentException missing = assertThrows(IllegalArgumentException.class,
                () -> LevixelAction.snapshot(actions, LevixelActionLayout.GRID));
        assertTrue(missing.getMessage().contains("actions[0].icon"));
        LevixelAction iconAction = new LevixelAction("a", "Action", "https://example.com/icon.png", null, false, false, null);
        assertEquals(1, LevixelAction.snapshot(Arrays.asList(iconAction), LevixelActionLayout.GRID).size());
        assertEquals(LevixelActionLayout.LIST, LevixelActionLayout.fromValue("list"));
        assertThrows(IllegalArgumentException.class, () -> LevixelActionLayout.fromValue("auto"));
    }

    @Test public void snapshotRejectsDuplicatesAndRetainsOpeningConfiguration() {
        List<LevixelAction> actions = new ArrayList<>(Arrays.asList(new LevixelAction("custom", "Custom", null)));
        List<LevixelAction> snapshot = LevixelAction.snapshot(actions);
        actions.clear();
        assertEquals("custom", snapshot.get(0).id);
        assertThrows(UnsupportedOperationException.class, () -> snapshot.clear());
        assertThrows(IllegalArgumentException.class, () -> LevixelAction.snapshot(Arrays.asList(snapshot.get(0), snapshot.get(0))));
        assertThrows(IllegalArgumentException.class, () -> new LevixelAction("", "Custom", null));
    }

    @Test public void eventsPreserveImmutableSessionMediaIdentityAndFailureState() {
        LevixelMediaItem item = new LevixelMediaItem("item-a", LevixelMediaItem.MediaType.VIDEO, "file:///movie.mp4", "file:///poster.jpg");
        LevixelViewerEvent action = new LevixelViewerEvent("action", "session-a", "gallery-a", 2, item, "inspect");
        assertEquals("item-a", action.payload.get("itemId"));
        assertEquals("inspect", action.payload.get("actionId"));
        assertEquals("video", action.payload.get("mediaType"));
        assertThrows(UnsupportedOperationException.class, () -> action.payload.put("itemId", "item-b"));
        LevixelViewerEvent failure = new LevixelViewerEvent("mediaError", "session-a", "gallery-a", 2, item, null);
        assertEquals("LOAD_FAILED", failure.payload.get("code"));
        assertFalse(failure.payload.containsKey("actionId"));
    }
}
