/**
 * profileConfig — a LISTA CANÔNICA das flags planas do perfil.
 *
 * Fonte da verdade do contrato: `plano/redesenho/22-plano-widget.md` §B.3.
 * Produtor: `WidgetProfile.resolve` (bloco 3.03) → `show.html.erb` /
 * `configs/create.json.jbuilder` (bloco 3.04) → `window.chatwootWebChannel.profileConfig`.
 * Consumidor: este arquivo, e só ele. `configMixin` e o store `appConfig` importam daqui —
 * ninguém mais lê `window.chatwootWebChannel.profileConfig` na mão.
 *
 * REGRA DURA (§B.3 / A3): o widget lê **flags planas**, nunca o nome do perfil.
 * `widgetProfile` existe só para telemetria e para o rótulo na tela de configuração.
 *
 * DEGRADAÇÃO: enquanto 3.04 não entregar a chave, `profileConfig` chega `undefined`.
 * Os defaults abaixo são o perfil `support` da §B.3, que é literalmente o comportamento de
 * hoje (A4: `nil` resolve para `support`). Ausência da chave ⇒ nada muda na tela.
 */

export const HOME_LAYOUTS = ['support', 'marketing'];
export const CAPTURE_FLOWS = ['form', 'conversational'];
export const PRIMARY_EXITS = ['none', 'whatsapp'];

export const PROFILE_CONFIG_DEFAULTS = Object.freeze({
  showKnowledgeBase: true,
  showConversationList: true,
  teaserEnabled: false,
  teaserDelayMs: 8000,
  teaserScrollPercent: 30,
  captureFlow: 'form',
  primaryExit: 'none',
  csatOnResolve: true,
  emailContinuity: true,
  homeLayout: 'support',
  aiLabelPersistent: true,
});

const asBoolean = (value, fallback) =>
  typeof value === 'boolean' ? value : fallback;

const asInteger = (value, fallback, { min, max } = {}) => {
  const parsed = typeof value === 'number' ? value : Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  if (min !== undefined && parsed < min) return fallback;
  if (max !== undefined && parsed > max) return fallback;
  return Math.trunc(parsed);
};

const asEnum = (value, allowed, fallback) =>
  allowed.includes(value) ? value : fallback;

/**
 * Normaliza o que o servidor mandou contra a lista canônica.
 *
 * Três garantias, e cada uma existe porque é um jeito conhecido de o consumo quebrar:
 *  1. chave ausente  → default da §B.3 (o widget não fica com `undefined` num `v-if`);
 *  2. chave com tipo/valor fora do contrato → default (servidor errado não apaga a tela);
 *  3. chave desconhecida → descartada (produtor novo não injeta comportamento sem consumidor).
 *
 * @param {object} [raw] o `profileConfig` cru de `window.chatwootWebChannel`
 * @returns {object} as 11 flags, sempre completas e sempre no tipo declarado
 */
export const resolveProfileConfig = (raw = {}) => {
  const source = raw && typeof raw === 'object' ? raw : {};
  const d = PROFILE_CONFIG_DEFAULTS;

  return {
    showKnowledgeBase: asBoolean(source.showKnowledgeBase, d.showKnowledgeBase),
    showConversationList: asBoolean(
      source.showConversationList,
      d.showConversationList
    ),
    teaserEnabled: asBoolean(source.teaserEnabled, d.teaserEnabled),
    teaserDelayMs: asInteger(source.teaserDelayMs, d.teaserDelayMs, { min: 0 }),
    teaserScrollPercent: asInteger(
      source.teaserScrollPercent,
      d.teaserScrollPercent,
      { min: 0, max: 100 }
    ),
    captureFlow: asEnum(source.captureFlow, CAPTURE_FLOWS, d.captureFlow),
    primaryExit: asEnum(source.primaryExit, PRIMARY_EXITS, d.primaryExit),
    csatOnResolve: asBoolean(source.csatOnResolve, d.csatOnResolve),
    emailContinuity: asBoolean(source.emailContinuity, d.emailContinuity),
    homeLayout: asEnum(source.homeLayout, HOME_LAYOUTS, d.homeLayout),
    aiLabelPersistent: asBoolean(source.aiLabelPersistent, d.aiLabelPersistent),
  };
};

/**
 * Lê o `profileConfig` de onde o servidor o escreveu.
 * Único ponto do widget que toca `window.chatwootWebChannel.profileConfig`.
 *
 * ACEITA AS DUAS GRAFIAS, e não é preciosismo — é um buraco que a rede não cobre.
 * A suíte de paridade 0.6 canonicaliza chave com `key.delete('_').downcase`, então
 * `profileConfig` num montador e `profile_config` no outro passam como equivalentes
 * e a paridade fica VERDE. Se este consumidor lesse só a forma camelCase, o widget
 * cairia nos defaults por um dos dois caminhos sem nada falhar em lugar nenhum —
 * a mesma forma do defeito do `tokens`, que ficou mudo atrás de um `||`.
 */
export const profileConfigFromChannel = (channelConfig = {}) => {
  const config = channelConfig || {};
  return resolveProfileConfig(config.profileConfig ?? config.profile_config);
};
