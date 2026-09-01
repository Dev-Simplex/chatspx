import emojiGroups from 'shared/components/emoji/emojisGroup.json';

// Recently used emojis persisted in localStorage.
const RECENT_EMOJI_KEY = 'emoji-icon-picker.recent-emojis';
const MAX_RECENT_EMOJIS = 16;

const matchesSearch = (emoji, term) =>
  emoji.slug.replaceAll('_', ' ').includes(term) ||
  emoji.name.toLowerCase().includes(term);

// Section names ship in English inside `emojisGroup.json` — they are data, not
// copy. `EMOJI.CATEGORIES.<SLUG>` holds the translated name and is the very
// dictionary the dashboard's EmojiInput has always read; this keeps both
// pickers on one mechanism. Falls back to the English name when the running
// locale (and its fallback) lack the key, which is what vue-i18n signals by
// echoing the key back.
export const translateCategoryName = (t, category) => {
  if (!category?.slug) return category?.name ?? '';
  const key = `EMOJI.CATEGORIES.${category.slug.toUpperCase()}`;
  // The slug set is closed and committed (the nine groups of
  // emojisGroup.json); the rule below guards against keys assembled from
  // runtime input, which this is not.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  const label = t(key);
  return label === key ? category.name : label;
};

// Emoji sections for the search term; prepends "Frequently used" when idle.
export const buildEmojiSections = (search, recentEmojis, frequentLabel) => {
  const term = search.trim().toLowerCase();
  if (term) {
    return emojiGroups
      .map(({ name, slug, emojis }) => ({
        name,
        // Without the slug the searching visitor gets untranslatable headings:
        // the idle branch below spreads the groups whole and keeps it, this
        // one used to rebuild the object and drop it.
        slug,
        emojis: emojis.filter(e => matchesSearch(e, term)),
      }))
      .filter(group => group.emojis.length);
  }
  return [
    ...(recentEmojis.length
      ? [{ name: frequentLabel, emojis: recentEmojis }]
      : []),
    ...emojiGroups,
  ];
};

// Samples an emoji's average color (via canvas) as a translucent hover tint. Cached per emoji.
const emojiTintCache = new Map();
const NEUTRAL_TINT = 'rgb(var(--slate-9) / 0.12)';

const sampleEmojiTint = emoji => {
  const canvas = Object.assign(document.createElement('canvas'), {
    width: 16,
    height: 16,
  });
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.font = '14px serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(emoji, 8, 9);

  const { data } = ctx.getImageData(0, 0, 16, 16);
  const pixels = Array.from(
    { length: data.length / 4 },
    (_, i) => i * 4
  ).filter(i => data[i + 3] > 16);
  if (!pixels.length) return NEUTRAL_TINT;

  const avg = offset =>
    Math.round(
      pixels.reduce((sum, i) => sum + data[i + offset], 0) / pixels.length
    );

  return `rgba(${avg(0)}, ${avg(1)}, ${avg(2)}, 0.16)`;
};

export const getEmojiTint = emoji => {
  if (!emojiTintCache.has(emoji)) {
    let tint = NEUTRAL_TINT;
    try {
      tint = sampleEmojiTint(emoji);
    } catch {
      /* canvas unavailable */
    }
    emojiTintCache.set(emoji, tint);
  }
  return emojiTintCache.get(emoji);
};

export const getRecentEmojis = () => {
  try {
    const stored = JSON.parse(localStorage.getItem(RECENT_EMOJI_KEY) ?? '[]');
    return Array.isArray(stored) ? stored : [];
  } catch {
    return [];
  }
};

export const addRecentEmoji = emoji => {
  const updated = [
    emoji,
    ...getRecentEmojis().filter(item => item.slug !== emoji.slug),
  ].slice(0, MAX_RECENT_EMOJIS);
  try {
    localStorage.setItem(RECENT_EMOJI_KEY, JSON.stringify(updated));
  } catch {
    /* private mode; recents are best-effort */
  }
  return updated;
};
