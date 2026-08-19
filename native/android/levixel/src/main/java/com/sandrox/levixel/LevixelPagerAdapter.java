package com.sandrox.levixel;

import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class LevixelPagerAdapter extends RecyclerView.Adapter<LevixelPagerAdapter.PageViewHolder> {
    public interface PageBindCallback {
        void onPageBound(@NonNull LevixelViewerPageView pageView, int position);
    }

    private final List<LevixelMediaItem> items = new ArrayList<>();
    private final Map<Integer, LevixelViewerPageView> attachedViews = new HashMap<>();
    @Nullable
    private final LevixelViewerPageView.Listener pageListener;
    @Nullable
    private final PageBindCallback pageBindCallback;
    private int activeIndex = -1;

    public LevixelPagerAdapter(
            @Nullable LevixelViewerPageView.Listener pageListener,
            @Nullable PageBindCallback pageBindCallback
    ) {
        this.pageListener = pageListener;
        this.pageBindCallback = pageBindCallback;
    }

    public void setItems(@NonNull List<LevixelMediaItem> list) {
        attachedViews.clear();
        items.clear();
        items.addAll(list);
        notifyDataSetChanged();
    }

    public void setActiveIndex(int index) {
        activeIndex = index;
        for (Map.Entry<Integer, LevixelViewerPageView> entry : attachedViews.entrySet()) {
            entry.getValue().setActive(entry.getKey() == index);
        }
    }

    public void releaseAll() {
        for (LevixelViewerPageView view : attachedViews.values()) {
            view.release();
        }
        attachedViews.clear();
    }

    @Nullable
    public LevixelViewerPageView findAttachedView(int position) {
        LevixelViewerPageView pageView = attachedViews.get(position);
        if (pageView == null) {
            return null;
        }
        if (!pageView.isAttachedToWindow()) {
            attachedViews.remove(position);
            return null;
        }
        return pageView;
    }

    @Nullable
    public LevixelViewerPageView findActiveView() {
        return attachedViews.get(activeIndex);
    }

    @NonNull
    @Override
    public PageViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        LevixelViewerPageView pageView = new LevixelViewerPageView(parent.getContext());
        pageView.setListener(pageListener);
        return new PageViewHolder(pageView);
    }

    @Override
    public void onBindViewHolder(@NonNull PageViewHolder holder, int position) {
        holder.pageView.bind(items.get(position));
        if (pageBindCallback != null) {
            pageBindCallback.onPageBound(holder.pageView, position);
        }
        holder.pageView.setActive(position == activeIndex);
    }

    @Override
    public void onViewAttachedToWindow(@NonNull PageViewHolder holder) {
        super.onViewAttachedToWindow(holder);
        removeAttachedViewKeys(holder.pageView);
        int position = holder.getBindingAdapterPosition();
        if (position == RecyclerView.NO_POSITION) {
            return;
        }
        attachedViews.put(position, holder.pageView);
    }

    @Override
    public void onViewDetachedFromWindow(@NonNull PageViewHolder holder) {
        super.onViewDetachedFromWindow(holder);
        removeAttachedViewKeys(holder.pageView);
    }

    @Override
    public void onViewRecycled(@NonNull PageViewHolder holder) {
        super.onViewRecycled(holder);
        removeAttachedViewKeys(holder.pageView);
        holder.pageView.release();
    }

    private void removeAttachedViewKeys(@NonNull LevixelViewerPageView pageView) {
        List<Integer> keys = new ArrayList<>();
        for (Map.Entry<Integer, LevixelViewerPageView> entry : attachedViews.entrySet()) {
            if (entry.getValue() == pageView) {
                keys.add(entry.getKey());
            }
        }
        for (Integer key : keys) {
            attachedViews.remove(key);
        }
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    static final class PageViewHolder extends RecyclerView.ViewHolder {
        final LevixelViewerPageView pageView;

        PageViewHolder(@NonNull LevixelViewerPageView itemView) {
            super(itemView);
            this.pageView = itemView;
        }
    }
}
