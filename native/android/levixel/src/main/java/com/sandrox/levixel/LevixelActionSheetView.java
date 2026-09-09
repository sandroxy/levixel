package com.sandrox.levixel;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.widget.NestedScrollView;
import com.bumptech.glide.Glide;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Content only. BottomSheetDialog owns placement, animation and dragging. */
final class LevixelActionSheetView extends LinearLayout {
    interface Selection { void select(LevixelAction action); }
    private static final int ICON_COLOR = 0xFF2F343B;
    private static final int LABEL_COLOR = 0xFF4B5057;
    private static final int CANCEL_COLOR = 0xFF445F83;
    private static final int DESTRUCTIVE_COLOR = 0xFFC73934;

    LevixelActionSheetView(Context context, List<LevixelAction> actions,
            LevixelActionLayout layout, boolean listIcons, Selection select, Runnable cancel) {
        super(context);
        setOrientation(VERTICAL);
        View topInset = new View(context);
        topInset.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        addView(topInset, new LayoutParams(-1, dp(layout == LevixelActionLayout.GRID ? 32 : 8)));

        NestedScrollView scrollView = new NestedScrollView(context);
        scrollView.setFillViewport(false);
        scrollView.setVerticalScrollBarEnabled(false);
        scrollView.setOverScrollMode(OVER_SCROLL_IF_CONTENT_SCROLLS);
        LinearLayout column = new LinearLayout(context);
        column.setOrientation(VERTICAL);
        scrollView.addView(column);
        // Weight lets long menus scroll while Cancel stays visible.
        addView(scrollView, new LayoutParams(-1, -2, 1));
        Map<String, List<LevixelAction>> groups = new LinkedHashMap<>();
        for (LevixelAction action : actions) {
            String key = action.group == null ? "" : action.group;
            if (!groups.containsKey(key)) groups.put(key, new ArrayList<>());
            groups.get(key).add(action);
        }
        int groupIndex = 0;
        for (List<LevixelAction> group : groups.values()) {
            if (layout == LevixelActionLayout.LIST) {
                if (groupIndex++ > 0) column.addView(new View(context), new LayoutParams(-1, dp(8)));
                for (int index = 0; index < group.size(); index++) {
                    if (index > 0) {
                        View divider = new View(context);
                        divider.setBackgroundColor(0x12000000);
                        LayoutParams dividerParams = new LayoutParams(-1, 1);
                        dividerParams.leftMargin = dividerParams.rightMargin = dp(24);
                        column.addView(divider, dividerParams);
                    }
                    column.addView(actionButton(group.get(index), false, listIcons, select), new LayoutParams(-1, -2));
                }
            } else {
                HorizontalScrollView scroll = new HorizontalScrollView(context);
                scroll.setHorizontalScrollBarEnabled(false);
                scroll.setOverScrollMode(OVER_SCROLL_IF_CONTENT_SCROLLS);
                LinearLayout row = new LinearLayout(context);
                row.setOrientation(HORIZONTAL);
                row.setPadding(dp(11), dp(8), dp(11), dp(16));
                for (LevixelAction action : group) {
                    row.addView(actionButton(action, true, true, select), new LayoutParams(dp(82), -2));
                }
                scroll.addView(row);
                column.addView(scroll, new LayoutParams(-1, -2));
            }
        }
        View separator = new View(context);
        separator.setBackgroundColor(0x12000000);
        LayoutParams separatorParams = new LayoutParams(-1, 1);
        separatorParams.topMargin = dp(8);
        addView(separator, separatorParams);
        TextView cancelButton = new TextView(context);
        cancelButton.setText(android.R.string.cancel);
        cancelButton.setTextColor(CANCEL_COLOR);
        cancelButton.setTextSize(16);
        cancelButton.setGravity(Gravity.CENTER);
        cancelButton.setFocusable(true);
        cancelButton.setBackground(ripple(0));
        cancelButton.setOnClickListener(v -> cancel.run());
        addView(cancelButton, new LayoutParams(-1, dp(56)));
        ViewCompat.setOnApplyWindowInsetsListener(this, (view, insets) -> {
            androidx.core.graphics.Insets safe = insets.getInsets(WindowInsetsCompat.Type.navigationBars() | WindowInsetsCompat.Type.displayCutout());
            setPadding(safe.left, 0, safe.right, safe.bottom + dp(16));
            return insets;
        });
        ViewCompat.setAccessibilityPaneTitle(this, "Media actions");
    }

    private View actionButton(LevixelAction action, boolean grid, boolean listIcons, Selection select) {
        Context context = getContext();
        LinearLayout button = new LinearLayout(context);
        button.setOrientation(grid ? VERTICAL : HORIZONTAL);
        button.setGravity(grid ? Gravity.CENTER_HORIZONTAL : Gravity.CENTER_VERTICAL);
        button.setPadding(dp(grid ? 5 : 24), dp(grid ? 0 : 12), dp(grid ? 5 : 24), dp(grid ? 0 : 12));
        if (!grid) button.setMinimumHeight(dp(64));
        button.setContentDescription(action.label);
        ViewCompat.setAccessibilityDelegate(button, new androidx.core.view.AccessibilityDelegateCompat() {
            @Override public void onInitializeAccessibilityNodeInfo(View host, androidx.core.view.accessibility.AccessibilityNodeInfoCompat info) {
                super.onInitializeAccessibilityNodeInfo(host, info);
                info.setClassName("android.widget.Button");
            }
        });
        button.setFocusable(true);
        button.setEnabled(!action.disabled);
        button.setAlpha(action.disabled ? .4f : 1f);
        button.setOnClickListener(v -> select.select(action));
        button.setBackground(ripple(grid ? 16 : 0));
        if (grid || listIcons) {
            FrameLayout slot = new FrameLayout(context);
            if (grid) slot.setBackground(rounded(0xFFFFFFFF, 16));
            if (action.icon != null) {
                ImageView icon = new ImageView(context);
                icon.setScaleType(ImageView.ScaleType.FIT_CENTER);
                int size = dp(grid ? 30 : 24);
                slot.addView(icon, new FrameLayout.LayoutParams(size, size, Gravity.CENTER));
                Glide.with(icon).load(action.icon)
                        .placeholder(R.drawable.levixel_action_placeholder)
                        .error(R.drawable.levixel_action_placeholder).into(icon);
            }
            slot.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
            LayoutParams slotParams = new LayoutParams(dp(grid ? 60 : 24), dp(grid ? 60 : 24));
            if (!grid) slotParams.rightMargin = dp(12);
            button.addView(slot, slotParams);
        }
        TextView label = new TextView(context);
        label.setText(action.label);
        label.setTextSize(grid ? 12 : 16);
        label.setTextColor(action.destructive ? DESTRUCTIVE_COLOR : LABEL_COLOR);
        label.setGravity(grid ? Gravity.TOP | Gravity.CENTER_HORIZONTAL : listIcons ? Gravity.CENTER_VERTICAL : Gravity.CENTER);
        if (grid) label.setMinLines(2);
        label.setMaxLines(2);
        label.setEllipsize(android.text.TextUtils.TruncateAt.END);
        if (grid) label.setPadding(0, dp(8), 0, 0);
        label.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        button.addView(label, grid ? new LayoutParams(-1, -2) : new LayoutParams(0, -2, 1));
        return button;
    }

    @Override protected void onMeasure(int widthSpec, int heightSpec) {
        int maximum = Math.round(getResources().getDisplayMetrics().heightPixels * .8f);
        if (MeasureSpec.getMode(heightSpec) != MeasureSpec.UNSPECIFIED) {
            maximum = Math.min(maximum, MeasureSpec.getSize(heightSpec));
        }
        super.onMeasure(widthSpec, MeasureSpec.makeMeasureSpec(maximum, MeasureSpec.AT_MOST));
    }

    private RippleDrawable ripple(int radius) {
        return new RippleDrawable(ColorStateList.valueOf(0x14000000), null, rounded(0xFFFFFFFF, radius));
    }

    private GradientDrawable rounded(int color, int radius) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(dp(radius));
        return shape;
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
