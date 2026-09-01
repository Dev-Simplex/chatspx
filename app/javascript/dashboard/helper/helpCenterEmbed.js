// Central de Ajuda embutida (iframe) — configuração única da frota.
//
// Regra de negócio (pedido Walisson, 08/07): em TODAS as VMs/contas o item
// "Central de Ajuda" do menu lateral abre o portal publicado embutido em
// iframe (somente leitura). A ÚNICA exceção é a conta autora — a conta 3 do
// deploy "de casa" (chat.simplexsolucoes.com.br) — que mantém o construtor
// completo (criar/editar artigos). Quando publicam lá, todos os outros já
// veem a atualização, pois todo mundo aponta pro mesmo portal publicado.

// Portal publicado que todos enxergam (somente leitura).
export const HELP_CENTER_PORTAL_URL =
  'https://chat.simplexsolucoes.com.br/hc/chatspx/pt_BR';

const HELP_CENTER_CONVERSATION_STORAGE_KEY = 'spx_help_center_conversation';
const HELP_CENTER_CONVERSATION_TTL = 365 * 24 * 60 * 60 * 1000;

// Deploy "de casa": precisa bater com o FRONTEND_URL da box de produção
// (window.chatwootConfig.hostURL vem do FRONTEND_URL). Nesta homolog o
// hostURL é https://chatspx.app, por isso a homolog NÃO é autora.
export const HELP_CENTER_AUTHORING_HOST = 'https://chat.simplexsolucoes.com.br';

// Conta que edita o Help Center no deploy de casa.
export const HELP_CENTER_AUTHORING_ACCOUNT_ID = 3;

const stripTrailingSlash = value => (value || '').replace(/\/+$/, '');

/**
 * Só a conta autora (host de casa + conta 3) mantém o construtor do Help
 * Center. Qualquer outra conta/VM cai no iframe somente-leitura.
 * @param {number|string} accountId
 * @returns {boolean}
 */
export const isHelpCenterAuthoringAccount = accountId => {
  const hostURL = stripTrailingSlash(window?.chatwootConfig?.hostURL);
  return (
    hostURL === stripTrailingSlash(HELP_CENTER_AUTHORING_HOST) &&
    Number(accountId) === HELP_CENTER_AUTHORING_ACCOUNT_ID
  );
};

/**
 * Monta a URL do portal embutível. `embed=true` libera o iframe cross-origin
 * (remove o X-Frame-Options no portal) MANTENDO o layout completo — inclusive
 * o widget "pedir ajuda". `theme` acompanha o light/dark do app.
 * @param {{ dark?: boolean }} [options]
 * @returns {string}
 */
export const getHelpCenterConversationToken = () => {
  try {
    const storedValue = window.localStorage.getItem(
      HELP_CENTER_CONVERSATION_STORAGE_KEY
    );
    if (!storedValue) return undefined;

    const { token, expiresAt } = JSON.parse(storedValue);
    if (token && expiresAt > Date.now()) return token;

    window.localStorage.removeItem(HELP_CENTER_CONVERSATION_STORAGE_KEY);
  } catch {
    return undefined;
  }

  return undefined;
};

export const persistHelpCenterConversationToken = token => {
  try {
    window.localStorage.setItem(
      HELP_CENTER_CONVERSATION_STORAGE_KEY,
      JSON.stringify({
        token,
        expiresAt: Date.now() + HELP_CENTER_CONVERSATION_TTL,
      })
    );
  } catch {
    // O painel segue funcional mesmo se o navegador bloquear storage.
  }
};

export const buildHelpCenterEmbedUrl = ({
  dark = false,
  conversationToken,
} = {}) => {
  const params = new URLSearchParams({
    embed: 'true',
    theme: dark ? 'dark' : 'light',
  });
  const fragment = conversationToken
    ? `#${new URLSearchParams({ cw_conversation: conversationToken })}`
    : '';
  return `${HELP_CENTER_PORTAL_URL}?${params.toString()}${fragment}`;
};
