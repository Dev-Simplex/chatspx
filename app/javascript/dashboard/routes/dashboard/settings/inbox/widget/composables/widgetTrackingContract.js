/**
 * O contrato de `widget_tracking`, do lado da tela (bloco 5.06).
 *
 * TRES fontes da verdade, e nenhuma delas e este arquivo:
 *
 *  1. **`docs/tracking/contrato-de-eventos.md`** (bloco 5.03) — os doze eventos,
 *     campo por campo. Quem for acrescentar evento muda LA primeiro.
 *  2. **`WidgetTrackingProjection::PUBLIC_KEYS`** — o que sai para o site do
 *     cliente. O que nao estiver la nao chega ao widget.
 *  3. **`WidgetConfigurable::SECRET_KEY_PATTERN`** — o que a gravacao RECUSA.
 *
 * Aqui ficam so as copias que a tela precisa para avisar antes, e o spec
 * `specs/widgetTrackingContract.spec.js` le as tres fontes e falha nomeando o
 * que se separou.
 *
 * A REGRA QUE GOVERNA ESTA TELA: `widget_tracking` e publicado no HTML de TODA
 * pagina do site do cliente. Identificador publico (Pixel ID, Measurement ID)
 * ja aparece no HTML de qualquer site que use as tags — isso e publico de
 * verdade. Segredo (access token, api secret) permite ESCREVER em nome do
 * cliente, mora em tabela cifrada, e a gravacao aqui o recusa com 422.
 */

/** O que pode ser gravado em `widget_tracking` e sai na projecao publica. */
export const PUBLIC_TRACKING_KEYS = Object.freeze([
  'meta_pixel_id',
  'ga4_measurement_id',
  'google_ads_send_to',
  'event_map',
  'install_tags',
  'consent_mode',
  'test_mode',
  'lead_value',
]);

/**
 * T-C4.3 — os dois alvos de "instalar a tag que falta". Espelham
 * `WidgetTrackingSchema::INSTALL_TAG_TARGETS`, e o schema recusa qualquer
 * outro nome com 422 (`additionalProperties: false` dentro de
 * `install_tags`). Sao dois e nao um porque instalar o pixel da Meta e
 * instalar o gtag do Google sao autorizacoes diferentes: quem ja tem GTM quer
 * o Google vindo do container dele.
 */
export const INSTALL_TAG_TARGETS = Object.freeze(['meta', 'google']);

/**
 * DESLIGADO nos dois, e a ausencia da chave significa o mesmo (decisao **Q5**:
 * opt-in explicito, nunca por padrao). Este objeto e o valor de PARTIDA da
 * tela, nao um valor gravado: quem nunca marcou nada continua sem
 * `install_tags` no banco, e o widget le a ausencia como desligado.
 *
 * A consequencia de errar aqui nao e cosmetica — e um script de terceiro
 * injetado no site de um cliente que nunca pediu.
 */
export const DEFAULT_INSTALL_TAGS = Object.freeze({
  meta: false,
  google: false,
});

/** Os doze eventos do contrato (5.03), na ordem do documento. */
export const TRACKING_EVENTS = Object.freeze([
  'chatspx_widget_loaded',
  'chatspx_widget_opened',
  'chatspx_conversation_started',
  'chatspx_prechat_submitted',
  'chatspx_lead',
  'chatspx_lead_qualified',
  'chatspx_lead_disqualified',
  'chatspx_agent_engaged',
  'chatspx_meeting_scheduled',
  'chatspx_conversation_resolved',
  'chatspx_deal_won',
  'chatspx_deal_lost',
]);

/**
 * O mapa de fabrica: para onde cada evento vai em cada destino.
 *
 * `null` significa "nao mandar" — e nao "mandar com o nome vazio". Os nomes da
 * Meta sao os eventos padrao dela (`Contact`, `Lead`, `Purchase`…); os do GA4
 * sao `snake_case` como aquele destino espera.
 */
export const DEFAULT_EVENT_MAP = Object.freeze({
  chatspx_widget_loaded: { enabled: false, meta: null, ga4: null },
  chatspx_widget_opened: { enabled: false, meta: null, ga4: 'widget_open' },
  chatspx_conversation_started: {
    enabled: true,
    meta: 'Contact',
    ga4: 'conversation_start',
  },
  chatspx_prechat_submitted: {
    enabled: true,
    meta: 'CompleteRegistration',
    ga4: 'prechat_submit',
  },
  chatspx_lead: { enabled: true, meta: 'Lead', ga4: 'generate_lead' },
  chatspx_lead_qualified: {
    enabled: false,
    meta: 'QualifiedLead',
    ga4: 'qualify_lead',
  },
  chatspx_lead_disqualified: { enabled: false, meta: null, ga4: null },
  chatspx_agent_engaged: { enabled: false, meta: null, ga4: 'agent_engaged' },
  chatspx_meeting_scheduled: {
    enabled: false,
    meta: 'Schedule',
    ga4: 'schedule',
  },
  chatspx_conversation_resolved: {
    enabled: false,
    meta: null,
    ga4: 'conversation_resolved',
  },
  chatspx_deal_won: { enabled: false, meta: 'Purchase', ga4: 'purchase' },
  chatspx_deal_lost: { enabled: false, meta: null, ga4: null },
});

/** Modos de valor do lead — quanto vale a conversao que a tela reporta. */
export const LEAD_VALUE_MODES = Object.freeze(['off', 'fixed', 'by_rule']);

/**
 * O modo teste desliga sozinho. Sete dias e o prazo do plano: mais que isso e
 * um cliente medindo o proprio teste como se fosse venda por um mes.
 */
export const TEST_MODE_MAX_DAYS = 7;

export const TRACKING_LIMITS = Object.freeze({
  metaPixelIdPattern: /^\d{15,16}$/,
  ga4MeasurementIdPattern: /^G-[A-Z0-9]{6,12}$/,
  googleAdsSendToPattern: /^AW-\d{9,11}\/[\w-]{6,32}$/,
  testEventCodeMaxLength: 32,
});

/** `chatspx_lead_qualified` -> `LEAD_QUALIFIED`, a chave de i18n. */
export const eventLabelKey = nome =>
  `INBOX_WIDGET.TRACKING.EVENTS.${nome.replace(/^chatspx_/, '').toUpperCase()}`;

export const isTestModeExpired = (startedAt, agora = Date.now()) => {
  if (!startedAt) return false;
  const inicio = new Date(startedAt).getTime();
  if (Number.isNaN(inicio)) return false;
  return agora - inicio > TEST_MODE_MAX_DAYS * 24 * 60 * 60 * 1000;
};
