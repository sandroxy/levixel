package com.sandrox.levixel;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.drawable.BitmapDrawable;
import android.view.View;
import android.widget.ImageView;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public final class LevixelClippedSnapshotTest {
    @Test public void clippedSnapshotsMatchTheOriginalRoundedSourcePixels() {
        for (RectF clip : new RectF[] {
                new RectF(0, 0, 100, 100), new RectF(0, 0, 100, 50),
                new RectF(0, 50, 100, 100), new RectF(0, 0, 50, 100),
                new RectF(50, 0, 100, 100), new RectF(8, 8, 85, 86) }) {
            Bitmap media = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888);
            media.eraseColor(Color.RED);
            ImageView source = new ImageView(RuntimeEnvironment.getApplication());
            source.setImageBitmap(media);
            source.setScaleType(ImageView.ScaleType.FIT_XY);
            source.layout(0, 0, 100, 100);
            LevixelSharedElementState state = LevixelLayoutSupport.captureImageViewState(source, clip, 20);
            assertNotNull(state);
            assertEquals(clip, state.getGeometry().getVisibleFrameInWindow());
            assertEquals(new RectF(-clip.left, -clip.top, 100 - clip.left, 100 - clip.top),
                    state.getGeometry().getRoundedFrameInVisibleBounds());
            assertSourcePixels(state.getGeometry(), media, clip);

            LevixelSourceHint hint = new LevixelSourceHint(new RectF(0, 0, 100, 100), clip,
                    100, 100, LevixelSourceHint.ObjectFit.FILL, 20);
            LevixelSharedElementGeometry hinted = hint.resolveGeometry(new RectF(0, 0, 100, 100), null);
            assertNotNull(hinted);
            assertSourcePixels(hinted, media, clip);
            source.setImageDrawable(null);
            media.recycle();
        }
    }

    @Test public void insetAspectFitContentDoesNotAcquireRoundedCorners() {
        Bitmap media = Bitmap.createBitmap(100, 40, Bitmap.Config.ARGB_8888);
        media.eraseColor(Color.RED);
        ImageView source = new ImageView(RuntimeEnvironment.getApplication());
        source.setImageBitmap(media);
        source.setScaleType(ImageView.ScaleType.FIT_CENTER);
        source.layout(0, 0, 100, 100);
        LevixelSharedElementState state = LevixelLayoutSupport.captureImageViewState(
                source, new RectF(0, 0, 100, 100), 20);
        assertNotNull(state);
        Bitmap rendered = render(state.getGeometry(), media);
        try {
            assertEquals(255, Color.alpha(rendered.getPixel(1, 1)));
            assertEquals(255, Color.alpha(rendered.getPixel(98, 38)));
        } finally { rendered.recycle(); media.recycle(); }
    }

    private void assertSourcePixels(LevixelSharedElementGeometry geometry, Bitmap media, RectF clip) {
        Bitmap rendered = render(geometry, media);
        Bitmap expected = Bitmap.createBitmap(rendered.getWidth(), rendered.getHeight(), Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(expected);
        canvas.translate(-clip.left, -clip.top);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.RED);
        canvas.drawRoundRect(new RectF(0, 0, 100, 100), 20, 20, paint);
        try {
            for (int y = 1; y < expected.getHeight(); y += 3) {
                for (int x = 1; x < expected.getWidth(); x += 3) {
                    int alpha = Color.alpha(expected.getPixel(x, y));
                    if (alpha < 20 || alpha > 235) {
                        assertEquals("Clipped source " + clip + " at " + x + "," + y,
                                alpha, Color.alpha(rendered.getPixel(x, y)), 20);
                    }
                }
            }
        } finally { rendered.recycle(); expected.recycle(); }
    }

    private Bitmap render(LevixelSharedElementGeometry geometry, Bitmap media) {
        LevixelTransitionSnapshotView snapshot = new LevixelTransitionSnapshotView(
                RuntimeEnvironment.getApplication(), new BitmapDrawable(
                        RuntimeEnvironment.getApplication().getResources(), media));
        snapshot.applyGeometry(geometry);
        int width = Math.round(geometry.getVisibleFrameInWindow().width());
        int height = Math.round(geometry.getVisibleFrameInWindow().height());
        snapshot.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
        snapshot.layout(0, 0, width, height);
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        snapshot.draw(new Canvas(bitmap));
        return bitmap;
    }
}
