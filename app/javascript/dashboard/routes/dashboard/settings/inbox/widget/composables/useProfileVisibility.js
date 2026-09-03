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

export const WIDGET_PROFILES = Object.freeze(['support', 'marketing']);
export const DEFAULT_PROFILE = 'support';

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
 * `field` casa com a chave logica de `widgetConfigFields.js` quando ha uma;
 * `path` diz onde o valor mora para quem for aplicar.
 */
export const PROFILE_PROPOSALS = Object.freeze({
  support: [
    {
      id: 'preChatFormEnabled',
      path: 'channel.pre_chat_form_enabled',
      value: false,
    },
    {
      id: 'triggersPreset',
      path: 'additional_attributes.widget_triggers',
      value: 'none',
    },
    {
      id: 'continuityViaEmail',
      path: 'channel.continuity_via_email',
      value: true,
    },
    { id: 'csatSurveyEnabled', path: 'csat_survey_enabled', value: true },
    {
      id: 'knowledgeBase',
      path: 'profileConfig.showKnowledgeBase',
      value: true,
    },
  ],
  marketing: [
    {
      id: 'preChatFormEnabled',
      path: 'channel.pre_chat_form_enabled',
      value: true,
    },
    {
      id: 'triggersPreset',
      path: 'additional_attributes.widget_triggers',
      value: 'teaser_8s_30pct',
    },
    {
      id: 'continuityViaEmail',
      path: 'channel.continuity_via_email',
      value: false,
    },
    { id: 'csatSurveyEnabled', path: 'csat_survey_enabled', value: false },
    {
      id: 'knowledgeBase',
      path: 'profileConfig.showKnowledgeBase',
      value: false,
    },
  ],
});

export const normalizeProfile = value =>
  WIDGET_PROFILES.includes(value) ? value : DEFAULT_PROFILE;

export const otherProfile = profile =>
  normalizeProfile(profile) === 'support' ? 'marketing' : 'support';

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
