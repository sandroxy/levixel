package com.sandrox.levixel.uniapp.runtime;

import com.sandrox.levixel.LevixelViewerEvent;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Test;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

public final class LevixelUniSessionTest {
    @Test
    public void closeBeforeMountFinishesOpeningBeforeResolvingClose() throws Exception {
        List<String> events = new ArrayList<>();
        LevixelUniSession session = unmountedSession(events);

        session.close(true, () -> events.add("closed"));
        session.close(true, () -> events.add("closed-again"));

        assertEquals(Arrays.asList("cancelled", "finished", "closed", "closed-again"), events);
        assertFalse(session.retry());
    }

    @Test
    public void closeCompletionCanCloseAgainWithoutRepeatingSessionEvents() throws Exception {
        List<String> events = new ArrayList<>();
        LevixelUniSession session = unmountedSession(events);

        session.close(false, () -> {
            events.add("closed");
            session.close(false, () -> events.add("closed-again"));
        });

        assertEquals(Arrays.asList("cancelled", "finished", "closed", "closed-again"), events);
    }

    private LevixelUniSession unmountedSession(List<String> events) throws Exception {
        Map<String, Object> item = new HashMap<>();
        item.put("id", "image");
        item.put("type", "image");
        item.put("url", "https://example.test/image.jpg");
        LevixelUniContract.OpenRequest request = LevixelUniContract.parseOpenRequest(
                Collections.singletonMap("items", Collections.singletonList(item)));
        // No Android views are created before start; a cancelled opening must still settle.
        return new LevixelUniSession(null, null, request, new LevixelUniSession.Listener() {
            @Override public void onOpened(LevixelUniSession session) { events.add("opened"); }
            @Override public void onViewerEvent(LevixelUniSession session, LevixelViewerEvent event) {}
            @Override public void onOpenCancelled(LevixelUniSession session) { events.add("cancelled"); }
            @Override public void onIndexChange(LevixelUniSession session, int previous, int current) {}
            @Override public void onDismissed(LevixelUniSession session, boolean emitDismissEvent) {
                assertFalse(emitDismissEvent);
                events.add("finished");
            }
        });
    }
}
