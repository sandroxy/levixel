import {
  onLevixelEvent,
  onLevixelSourceActivate,
  openLevixelFromSelector,
  warmupLevixelItem,
  type LevixelMediaItem,
} from '../src/index.js';

const items: LevixelMediaItem[] = [
  { id: 'portrait-dog', type: 'image', url: 'https://picsum.photos/id/1025/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1025/400/600', width: 1600, height: 2400, alt: 'Portrait Dog' },
  { id: 'big-buck-bunny', type: 'video', url: 'https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4', posterUrl: 'https://picsum.photos/id/1024/800/450', width: 16, height: 9, alt: 'Big Buck Bunny' },
  { id: 'mountain-falls', type: 'image', url: 'https://picsum.photos/id/1035/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1035/400/600', width: 1600, height: 2400, alt: 'Mountain Falls' },
  { id: 'wide-coast', type: 'image', url: 'https://picsum.photos/id/1050/2400/1600', thumbnailUrl: 'https://picsum.photos/id/1050/600/400', width: 2400, height: 1600, alt: 'Wide Coast' },
  { id: 'bunny-trailer', type: 'video', url: 'https://media.w3.org/2010/05/bunny/trailer.mp4', posterUrl: 'https://picsum.photos/id/1044/800/450', width: 16, height: 9, alt: 'Bunny Trailer' },
  { id: 'river', type: 'image', url: 'https://picsum.photos/id/1015/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1015/400/600', width: 1600, height: 2400, alt: 'River' },
  { id: 'valley', type: 'image', url: 'https://picsum.photos/id/1018/2400/1600', thumbnailUrl: 'https://picsum.photos/id/1018/600/400', width: 2400, height: 1600, alt: 'Valley' },
  { id: 'portrait-rock', type: 'image', url: 'https://picsum.photos/id/1003/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1003/400/600', width: 1600, height: 2400, alt: 'Portrait Rock' },
  { id: 'lake', type: 'image', url: 'https://picsum.photos/id/1011/2400/1600', thumbnailUrl: 'https://picsum.photos/id/1011/600/400', width: 2400, height: 1600, alt: 'Lake' },
  { id: 'portrait-woman', type: 'image', url: 'https://picsum.photos/id/1027/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1027/400/600', width: 1600, height: 2400, alt: 'Portrait Woman' },
  { id: 'desert', type: 'image', url: 'https://picsum.photos/id/1002/2400/1600', thumbnailUrl: 'https://picsum.photos/id/1002/600/400', width: 2400, height: 1600, alt: 'Desert' },
  { id: 'flower-video', type: 'video', url: 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4', posterUrl: 'https://picsum.photos/id/1069/800/450', width: 16, height: 9, alt: 'Flower Video' },
  { id: 'forest', type: 'image', url: 'https://picsum.photos/id/1043/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1043/400/600', width: 1600, height: 2400, alt: 'Forest' },
  { id: 'city', type: 'image', url: 'https://picsum.photos/id/1049/2400/1600', thumbnailUrl: 'https://picsum.photos/id/1049/600/400', width: 2400, height: 1600, alt: 'City' },
  { id: 'sintel-trailer', type: 'video', url: 'https://media.w3.org/2010/05/sintel/trailer.mp4', posterUrl: 'https://picsum.photos/id/1070/800/450', width: 16, height: 9, alt: 'Sintel Trailer' },
  { id: 'portrait-road', type: 'image', url: 'https://picsum.photos/id/1060/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1060/400/600', width: 1600, height: 2400, alt: 'Portrait Road' },
  { id: 'cliffs', type: 'image', url: 'https://picsum.photos/id/1074/2400/1600', thumbnailUrl: 'https://picsum.photos/id/1074/600/400', width: 2400, height: 1600, alt: 'Cliffs' },
  { id: 'portrait-field', type: 'image', url: 'https://picsum.photos/id/1084/1600/2400', thumbnailUrl: 'https://picsum.photos/id/1084/400/600', width: 1600, height: 2400, alt: 'Portrait Field' },
];

const gallery = document.querySelector<HTMLElement>('#gallery');
const status = document.querySelector<HTMLElement>('#status');
if (!gallery || !status)
  throw new Error('Levixel demo host is incomplete');

items.forEach((item, index) => {
  const card = document.createElement('button');
  card.type = 'button';
  card.className = 'card levixel-demo-source';
  card.dataset.index = String(index);
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
        index,
        sourceSelector: '.levixel-demo-source',
        sourceStyles: items.map(() => ({ objectFit: 'cover', cornerRadius: 14 })),
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
