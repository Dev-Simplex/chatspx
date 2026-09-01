import { LocalStorage } from 'shared/helpers/localStorage';

// A escolha do numero precisa sobreviver a troca de aba e ao reload — sem isso o
// supervisor volta para o consolidado a cada visita e o filtro nao serve para nada.
const STORAGE_KEY = 'reports_inbox_scope';

export const readInboxScope = () =>
  Number(LocalStorage.get(STORAGE_KEY)) || null;

export const writeInboxScope = inboxId =>
  LocalStorage.set(STORAGE_KEY, inboxId || '');
