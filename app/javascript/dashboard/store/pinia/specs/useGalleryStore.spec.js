import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Evita puxar axios real do GalleryAPI
vi.mock('../../../api/gallery', () => ({
  default: { list: vi.fn(), links: vi.fn() },
}));

import { useGalleryStore, GALLERY_TAB } from '../useGalleryStore';

describe('useGalleryStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "gallery"', () => {
    const store = useGalleryStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('gallery');
  });

  it('starts on MEDIA tab', () => {
    const store = useGalleryStore();
    expect(store.getCurrentTab).toBe(GALLERY_TAB.MEDIA);
  });

  it('hasMore returns false on initial state', () => {
    const store = useGalleryStore();
    expect(store.hasMore(GALLERY_TAB.MEDIA)).toBe(false);
  });
});
