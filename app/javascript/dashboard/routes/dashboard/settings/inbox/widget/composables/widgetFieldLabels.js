/**
 * O nome humano de cada campo do rascunho.
 *
 * A barra de salvar diz quantas alteracoes ha; o dialogo de saida e o de troca
 * de perfil dizem QUAIS. Para dizer "quais" sem inventar string no meio do
 * componente, a chave logica do campo vira chave de i18n por uma regra unica —
 * e um teste percorre `KNOWN_FIELD_PATHS` e falha se qualquer uma faltar em
 * `pt_BR` ou em `en`. Chave dinamica nao e varrida pelo grep de `$t()`; a lista
 * abaixo e o que torna a cobertura verificavel.
 */
import {
  WIDGET_CONFIG_FIELDS,
  DEFAULT_APPEARANCE,
  DEFAULT_TRIGGERS,
  DEFAULT_TRACKING,
} from './widgetConfigFields';

const GROUP_SUBFIELDS = {
  appearance: Object.keys(DEFAULT_APPEARANCE),
  triggers: Object.keys(DEFAULT_TRIGGERS),
  tracking: Object.keys(DEFAULT_TRACKING),
};

/** `appearance.offset_x` -> `INBOX_WIDGET.FIELDS.APPEARANCE_OFFSET_X` */
export const fieldLabelKey = path =>
  `INBOX_WIDGET.FIELDS.${String(path)
    .replace(/\./g, '_')
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .toUpperCase()}`;

export const KNOWN_FIELD_PATHS = WIDGET_CONFIG_FIELDS.flatMap(field =>
  field.group
    ? (GROUP_SUBFIELDS[field.key] ?? []).map(sub => `${field.key}.${sub}`)
    : [field.key]
);

/**
 * Traduz a lista que `dirtyFields` devolve, na ordem em que ela veio.
 *
 * A chave e dinamica de proposito — sao 22 campos e a alternativa e um `switch`
 * de 22 ramos que o proximo campo esquece de atualizar. O que o lint protege
 * (chave que existe no codigo e nao no JSON) esta coberto por
 * `specs/inboxWidgetI18n.spec.js`, que percorre `KNOWN_FIELD_PATHS` e falha
 * nomeando a chave que faltar em pt_BR ou em en.
 */
export const labelsForFields = (paths, t) =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  paths.map(path => t(fieldLabelKey(path)));
