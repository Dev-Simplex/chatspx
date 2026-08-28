/**
 * O perfil da inbox — o que ele esconde, e o que ele PROPOE mudar.
 *
 * Duas regras governam este arquivo, e as duas vieram de decisao explicita do
 * plano (23-plano §B.1.3 e §B.1.4, arbitragem A3):
 *
 *  1. **Perfil ESCONDE, nao remove.** Toda secao oculta continua alcancavel
 *     pelo link "mostrar configuracoes de {outro perfil}". Um cliente de
 *     suporte que queira medir conversao nao pode ficar refem do rotulo.
 *  2. **Trocar o perfil PROPOE, nunca reescreve.** O que ja esta gravado so
 *     muda com confirmacao explicita, item a item. Perda silenciosa de
 *     configuracao e a falha mais cara que uma tela de settings pode ter.
 *
 * `nil` e lido como `support` (A4: sem backfill) — que e literalmente o
 * comportamento de hoje.
 */
import { computed, ref, unref } from 'vue';
import { RECOMMENDED_TRIGGERS } from './widgetTriggersContract';

export const WIDGET_PROFILES = Object.freeze(['support', 'marketing']);
export const DEFAULT_PROFILE = 'support';

export const normalizeProfile = value =>
  WIDGET_PROFILES.includes(value) ? value : DEFAULT_PROFILE;

export const otherProfile = profile =>
  normalizeProfile(profile) === 'support' ? 'marketing' : 'support';

/**
 * A matriz de visibilidade. `true` = a secao aparece nesse perfil.
 * Os ids sao os das SECOES das quatro telas — o perfil nunca esconde campo
 * solto no meio de uma secao.
 */
export const PROFILE_SECTIONS = Object.freeze({
  'appearance.launcherExpanded': { support: false, marketing: true },
  triggers: { support: false, marketing: true },
  'triggers.segmentation': { support: false, marketing: true },
  'prechat.builder': { support: false, marketing: true },
  'prechat.incompleteLead': { support: false, marketing: true },
  tracking: { support: false, marketing: true },
  csat: { support: true, marketing: false },
  nps: { support: true, marketing: false },
});

/**
 * O que a troca de perfil PROPOE gravar (regime 2 de A3). Cada entrada e um
 * campo que o administrador vai ver nominalmente no dialogo, com caixa
 * marcavel — e nada e escrito sem a marca dele.
 *
 * `field` casa com a chave logica de `widgetConfigFields.js`; `path` diz onde o
 * valor mora no PATCH, e existe para quem le a proposta de fora da tela.
 *
 * `derived: true` (bloco 3.07) marca a proposta que NAO tem campo gravado: ela
 * e consequencia do perfil, resolvida por `WidgetProfile::PROFILE_DEFAULTS` no
 * servidor (regime 3 de A3, "campos que nascem agora e nao tem valor gravado a
 * preservar"). O dialogo lista essa linha — o aceite manda listar tudo que muda
 * —, mas SEM caixa: oferecer uma caixa que nao muda nada quando desmarcada e a
 * mesma mentira que este bloco existe para tirar da tela.
 */
export const PROFILE_PROPOSALS = Object.freeze({
  support: [
    {
      id: 'preChatFormEnabled',
      field: 'preChatEnabled',
      path: 'channel.pre_chat_form_enabled',
      value: false,
    },
    {
      id: 'triggersPreset',
      field: 'triggers',
      path: 'additional_attributes.widget_triggers',
      value: 'none',
    },
    {
      id: 'continuityViaEmail',
      field: 'continuityViaEmail',
      path: 'channel.continuity_via_email',
      value: true,
    },
    {
      id: 'csatSurveyEnabled',
      field: 'csatSurveyEnabled',
      path: 'csat_survey_enabled',
      value: true,
    },
    {
      id: 'knowledgeBase',
      derived: true,
      path: 'profileConfig.showKnowledgeBase',
      value: true,
    },
  ],
  marketing: [
    {
      id: 'preChatFormEnabled',
      field: 'preChatEnabled',
      path: 'channel.pre_chat_form_enabled',
      value: true,
    },
    {
      id: 'triggersPreset',
      field: 'triggers',
      path: 'additional_attributes.widget_triggers',
      value: 'teaser_8s_30pct',
    },
    {
      id: 'continuityViaEmail',
      field: 'continuityViaEmail',
      path: 'channel.continuity_via_email',
      value: false,
    },
    {
      id: 'csatSurveyEnabled',
      field: 'csatSurveyEnabled',
      path: 'csat_survey_enabled',
      value: false,
    },
    {
      id: 'knowledgeBase',
      derived: true,
      path: 'profileConfig.showKnowledgeBase',
      value: false,
    },
  ],
});

/**
 * Os presets de gatilho que o perfil propoe, JA NA FORMA DO SCHEMA.
 *
 * O bloco 3.07 achou aqui um defeito que teria chegado a producao: a proposta
 * carregava a string `'teaser_8s_30pct'` e o aplicador ingenuo a escreveria em
 * `widget_triggers`, que `WidgetConfigurable#ensure_widget_config_objects`
 * exige que seja objeto. O PATCH inteiro voltaria 422 — e o administrador leria
 * "salvo" com o banco intacto. O nome do preset e a linguagem da PROPOSTA; a
 * estrutura abaixo e a linguagem da GRAVACAO, e a traducao entre as duas mora
 * num lugar so.
 *
 * `RECOMMENDED_TRIGGERS` vem do contrato dos gatilhos (8 s na pagina E 30% de
 * rolagem), que e conferido contra o Ruby por `widgetTriggersContract.spec.js`.
 */
export const TRIGGER_PRESETS = Object.freeze({
  none: Object.freeze({ enabled: false, triggers: Object.freeze([]) }),
  teaser_8s_30pct: Object.freeze({
    enabled: true,
    triggers: RECOMMENDED_TRIGGERS,
  }),
});

/**
 * O caminho inverso: que preset descreve o que esta gravado. Serve para o
 * `currentValues` do dialogo — sem ele, a troca proporia "ligar o teaser" para
 * quem ja esta com o teaser ligado.
 *
 * Qualquer combinacao que nao seja exatamente um dos dois presets e `custom`, e
 * `custom` nunca e igual a proposta nenhuma: quem mexeu nos gatilhos a mao
 * merece ver a proposta e decidir.
 */
export const triggersPresetOf = (triggers = {}) => {
  const lista = triggers.triggers ?? [];
  const ativos = lista.filter(
    item => item?.desktop?.enabled || item?.mobile?.enabled
  );

  if (!triggers.enabled && ativos.length === 0) return 'none';
  if (!triggers.enabled) return 'custom';

  const casaComRecomendado =
    ativos.length === RECOMMENDED_TRIGGERS.length &&
    RECOMMENDED_TRIGGERS.every(preset => {
      const atual = lista.find(item => item.id === preset.id);
      return (
        atual?.desktop?.enabled === true &&
        atual?.desktop?.value === preset.desktop.value
      );
    });

  return casaComRecomendado ? 'teaser_8s_30pct' : 'custom';
};

/**
 * O `currentValues` do dialogo montado a partir do RASCUNHO da tela.
 *
 * Existe para que o dialogo compare com o que a caixa realmente tem — e nao com
 * um dublê. Tres defeitos desta base passaram por todos os testes porque o spec
 * do front dublava a resposta com um formato que o backend nunca devolveu.
 */
export const currentValuesFromDraft = (draft = {}) => ({
  preChatFormEnabled: Boolean(draft.preChatEnabled),
  triggersPreset: triggersPresetOf(draft.triggers ?? {}),
  continuityViaEmail: Boolean(draft.continuityViaEmail),
  csatSurveyEnabled: Boolean(draft.csatSurveyEnabled),
  // Derivada: o valor de hoje e o que o perfil de hoje resolve.
  knowledgeBase: normalizeProfile(draft.profile) === 'support',
});

/**
 * Traduz as propostas ACEITAS em escritas no rascunho — e e este o ouvinte que
 * faltava no `@apply`: sem ele, cada caixa que o administrador marcava caia no
 * chao com a tela dizendo que a troca fora aplicada.
 *
 * Proposta sem `field` e sem `derived` LANCA, de proposito. Uma proposta nova
 * acrescentada sem aplicador seria invisivel: a tela continuaria listando a
 * linha e continuaria nao gravando nada.
 */
export const profileWrites = (accepted = [], draft = {}) =>
  accepted.flatMap(proposal => {
    if (proposal.derived) return [];

    if (!proposal.field) {
      throw new Error(
        `[useProfileVisibility] proposta sem aplicador: ${proposal.id}`
      );
    }

    if (proposal.field === 'triggers') {
      const preset = TRIGGER_PRESETS[proposal.value];
      if (!preset) {
        throw new Error(
          `[useProfileVisibility] preset de gatilho desconhecido: ${proposal.value}`
        );
      }
      // O objeto do grupo viaja INTEIRO no PATCH (merge raso do controller):
      // preservar os irmaos — `approach`, `degrade_on_return`, `audience` — e o
      // que impede a troca de perfil de apagar a abordagem ja configurada.
      return [
        {
          key: 'triggers',
          value: { ...(draft.triggers ?? {}), ...preset },
        },
      ];
    }

    return [{ key: proposal.field, value: proposal.value }];
  });

/** As secoes que o perfil esconde — a lista que alimenta o link de escape. */
export const hiddenSectionsFor = profile => {
  const active = normalizeProfile(profile);
  return Object.entries(PROFILE_SECTIONS)
    .filter(([, visibility]) => !visibility[active])
    .map(([id]) => id);
};

export function useProfileVisibility(profile) {
  /** O escape da regra 1: ver o que o outro perfil configura, sem trocar nada. */
  const showOtherProfile = ref(false);

  const activeProfile = computed(() => normalizeProfile(unref(profile)));

  const isSectionVisible = sectionId => {
    const visibility = PROFILE_SECTIONS[sectionId];
    // Secao que nao esta na matriz e visivel nos dois perfis — a coluna
    // "sempre" da §B.1.3 e maior do que parece, e o default tem de ser ela.
    if (!visibility) return true;
    return visibility[activeProfile.value] || showOtherProfile.value;
  };

  return {
    activeProfile,
    otherProfile: computed(() => otherProfile(activeProfile.value)),
    hiddenSections: computed(() => hiddenSectionsFor(activeProfile.value)),
    showOtherProfile,
    isSectionVisible,
    toggleOtherProfile: () => {
      showOtherProfile.value = !showOtherProfile.value;
    },
  };
}

/**
 * O que a troca REALMENTE mudaria, dado o que ja esta gravado. Uma proposta
 * cujo valor ja e o proposto nao entra: listar "mudar CSAT para ligado" quando
 * ele ja esta ligado treina o administrador a clicar sem ler.
 */
export const pendingProposals = (targetProfile, currentValues = {}) =>
  (PROFILE_PROPOSALS[normalizeProfile(targetProfile)] ?? []).filter(
    proposal =>
      !(proposal.id in currentValues) ||
      currentValues[proposal.id] !== proposal.value
  );

/** O espelho da lista acima: o que fica como esta, e continua gravado. */
export const keptValues = (targetProfile, currentValues = {}) =>
  (PROFILE_PROPOSALS[normalizeProfile(targetProfile)] ?? []).filter(
    proposal =>
      proposal.id in currentValues &&
      currentValues[proposal.id] === proposal.value
  );
