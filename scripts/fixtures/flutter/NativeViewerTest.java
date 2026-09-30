package com.sandrox.tests.levixel_source_host;

import androidx.test.rule.ActivityTestRule;
import dev.flutter.plugins.integration_test.FlutterTestRunner;
import org.junit.Rule;
import org.junit.runner.RunWith;

@RunWith(FlutterTestRunner.class)
public final class NativeViewerTest {
    @Rule
    public final ActivityTestRule<MainActivity> activity =
            new ActivityTestRule<>(MainActivity.class, true, false);
}
