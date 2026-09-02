import {
  onLevixelEvent,
  onLevixelSourceActivate,
  openLevixelFromSelector,
  warmupLevixelItem,
  type LevixelMediaItem,
} from '../src/index.js';

const items: LevixelMediaItem[] = [
  { id: 'portrait-dog', type: 'image', url: 'https://images.unsplash.com/photo-1552053831-71594a27632d?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1552053831-71594a27632d?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'Portrait Dog' },
  { id: 'big-buck-bunny', type: 'video', url: 'https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4', posterUrl: 'https://images.unsplash.com/photo-1585110396000-c9ffd4e4b308?fit=crop&fm=jpg&h=450&q=82&w=800', width: 16, height: 9, alt: 'Big Buck Bunny' },
  { id: 'mountain-falls', type: 'image', url: 'https://images.unsplash.com/photo-1506882216359-7b380b0c746c?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1506882216359-7b380b0c746c?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'Mountain Falls' },
  { id: 'wide-coast', type: 'image', url: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?fit=crop&fm=jpg&h=1600&q=82&w=2400', thumbnailUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?fit=crop&fm=jpg&h=400&q=82&w=600', width: 2400, height: 1600, alt: 'Wide Coast' },
  { id: 'bunny-trailer', type: 'video', url: 'https://media.w3.org/2010/05/bunny/trailer.mp4', posterUrl: 'https://images.unsplash.com/photo-1591561582301-7ce6588cc286?fit=crop&fm=jpg&h=450&q=82&w=800', width: 16, height: 9, alt: 'Bunny Trailer' },
  { id: 'river', type: 'image', url: 'https://images.unsplash.com/photo-1437482078695-73f5ca6c96e2?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1437482078695-73f5ca6c96e2?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'River' },
  { id: 'valley', type: 'image', url: 'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?fit=crop&fm=jpg&h=1600&q=82&w=2400', thumbnailUrl: 'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?fit=crop&fm=jpg&h=400&q=82&w=600', width: 2400, height: 1600, alt: 'Valley' },
  { id: 'portrait-rock', type: 'image', url: 'https://images.unsplash.com/photo-1519681393784-d120267933ba?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1519681393784-d120267933ba?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'Portrait Rock' },
  { id: 'lake', type: 'image', url: 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?fit=crop&fm=jpg&h=1600&q=82&w=2400', thumbnailUrl: 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?fit=crop&fm=jpg&h=400&q=82&w=600', width: 2400, height: 1600, alt: 'Lake' },
  { id: 'portrait-pines', type: 'image', url: 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'Sunlit Pines' },
  { id: 'desert', type: 'image', url: 'https://images.unsplash.com/photo-1509316785289-025f5b846b35?fit=crop&fm=jpg&h=1600&q=82&w=2400', thumbnailUrl: 'https://images.unsplash.com/photo-1509316785289-025f5b846b35?fit=crop&fm=jpg&h=400&q=82&w=600', width: 2400, height: 1600, alt: 'Desert' },
  { id: 'flower-video', type: 'video', url: 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4', posterUrl: 'https://images.unsplash.com/photo-1526047932273-341f2a7631f9?fit=crop&fm=jpg&h=450&q=82&w=800', width: 16, height: 9, alt: 'Flower Video' },
  { id: 'forest', type: 'image', url: 'https://images.unsplash.com/photo-1473448912268-2022ce9509d8?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1473448912268-2022ce9509d8?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'Forest' },
  { id: 'city', type: 'image', url: 'https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?fit=crop&fm=jpg&h=1600&q=82&w=2400', thumbnailUrl: 'https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?fit=crop&fm=jpg&h=400&q=82&w=600', width: 2400, height: 1600, alt: 'City' },
  { id: 'sintel-trailer', type: 'video', url: 'https://media.w3.org/2010/05/sintel/trailer.mp4', posterUrl: 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?fit=crop&fm=jpg&h=450&q=82&w=800', width: 16, height: 9, alt: 'Sintel Trailer' },
  { id: 'portrait-road', type: 'image', url: 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'Portrait Road' },
  { id: 'cliffs', type: 'image', url: 'https://images.unsplash.com/photo-1570507318899-bd3f2ed3f24e?fit=crop&fm=jpg&h=1600&q=82&w=2400', thumbnailUrl: 'https://images.unsplash.com/photo-1570507318899-bd3f2ed3f24e?fit=crop&fm=jpg&h=400&q=82&w=600', width: 2400, height: 1600, alt: 'Cliffs' },
  { id: 'portrait-field', type: 'image', url: 'https://images.unsplash.com/photo-1500382017468-9049fed747ef?fit=crop&fm=jpg&h=2400&q=82&w=1600', thumbnailUrl: 'https://images.unsplash.com/photo-1500382017468-9049fed747ef?fit=crop&fm=jpg&h=600&q=82&w=400', width: 1600, height: 2400, alt: 'Portrait Field' },
];

const gallery = document.querySelector<HTMLElement>('#gallery');
const status = document.querySelector<HTMLElement>('#status');
if (!gallery || !status)
  throw new Error('Levixel demo host is incomplete');

items.forEach((item, index) => {
  const card = document.createElement('button');
  card.type = 'button';
  card.className = 'card levixel-demo-source';
  card.id = `levixel-demo-source-${index}`;
  card.dataset.index = String(index);
  card.dataset.itemId = item.id;
  card.setAttribute('aria-label', `Open ${item.alt ?? item.id}`);
  const image = document.createElement('img');
  image.src = item.type === 'video'
    ? (item.posterUrl ?? item.thumbnailUrl ?? item.url)
    : (item.thumbnailUrl ?? item.url);
  image.alt = item.alt ?? '';
  image.loading = index < 6 ? 'eager' : 'lazy';
  image.decoding = 'async';
  image.addEventListener('load', event => void warmupLevixelItem(item, event));
  const label = document.createElement('span');
  label.className = 'label';
  label.textContent = item.alt ?? item.id;
  card.append(image, label);
  if (item.type === 'video') {
    const badge = document.createElement('span');
    badge.className = 'video-badge';
    badge.textContent = '▶ VIDEO';
    card.append(badge);
  }
  const openCard = async (): Promise<void> => {
    status.textContent = `Opening ${item.alt ?? item.id}…`;
    try {
      const result = await openLevixelFromSelector({
        items,
        initialItemId: item.id,
        sourceBindings: [...gallery.querySelectorAll<HTMLElement>('.levixel-demo-source')]
          .map(source => ({
            itemId: source.dataset.itemId!,
            selector: `#${source.id}`,
            objectFit: 'cover',
            cornerRadius: 14,
          })),
      });
      status.textContent = `Opened ${result.index + 1} of ${result.count}`;
    }
    catch (error) {
      status.textContent = error instanceof Error ? error.message : 'Unable to open Levixel';
    }
  };
  onLevixelSourceActivate(card, () => { void openCard(); });
  gallery.append(card);
});

onLevixelEvent((event) => {
  if (event.type === 'indexChange')
    status.textContent = `Current index: ${String(event.payload.currentIndex)}`;
  else if (event.type === 'dismiss')
    status.textContent = 'Viewer dismissed';
});
