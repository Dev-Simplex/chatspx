import { LocalStorage } from './localStorage';

/**
 * Emojis usados recentemente.
 *
 * Vive em `shared/` porque o picker (EmojiInput.vue) é compartilhado entre o
 * dashboard e o widget — logo não pode depender do store/ui_settings do
 * dashboard. A persistência é local ao navegador, no mesmo padrão de
 * "Buscas recentes" (RecentSearches.vue).
 */
export const RECENT_EMOJIS_STORAGE_KEY = 'recentEmojis';

// Duas linhas cheias na grade do picker (largura w-80 → 9 emojis por linha).
export const MAX_RECENT_EMOJIS = 18;

/**
 * @returns {string[]} emojis do mais recente para o mais antigo
 */
export const getRecentEmojis = () => {
  const stored = LocalStorage.get(RECENT_EMOJIS_STORAGE_KEY);
  if (!Array.isArray(stored)) return [];

  return stored
    .filter(emoji => typeof emoji === 'string' && emoji !== '')
    .slice(0, MAX_RECENT_EMOJIS);
};

/**
 * Move o emoji para o topo da lista de recentes (sem duplicar).
 *
 * @param {string} emoji caractere do emoji
 * @returns {string[]} a lista já atualizada
 */
export const addRecentEmoji = emoji => {
  if (typeof emoji !== 'string' || emoji === '') return getRecentEmojis();

  const updated = [
    emoji,
    ...getRecentEmojis().filter(item => item !== emoji),
  ].slice(0, MAX_RECENT_EMOJIS);

  try {
    LocalStorage.set(RECENT_EMOJIS_STORAGE_KEY, updated);
  } catch (error) {
    // Quota cheia ou storage indisponível (aba anônima): recentes é um
    // conforto, nunca deve derrubar o envio do emoji.
  }

  return updated;
};
