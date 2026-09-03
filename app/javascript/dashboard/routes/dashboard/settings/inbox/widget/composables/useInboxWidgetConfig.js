/**
 * useInboxWidgetConfig — o rascunho das quatro telas novas do widget.
 *
 * Regra unica, e ela e a razao do composable existir (23-plano §B.0.2):
 * **nada vai ao servidor sozinho e nada muta o objeto do store.** Toda edicao
 * cai num rascunho local; `isDirty` compara rascunho com o que esta gravado;
 * `save()` monta o PATCH so com o que mudou; `discard()` volta ao gravado.
 *
 * Duas convencoes conflitantes convivem hoje na mesma superficie — a aba 1
 * salva tudo num botao (`Settings.vue`) e a aba 7 salva a cada toggle
 * (`ConfigurationPage.vue`). As telas novas usam rascunho explicito porque tres
 * das quatro tem campos interdependentes: a cor muda o contraste calculado, o
 * perfil muda quais secoes existem, um gatilho tem seis subcampos. Salvamento
 * automatico em campo interdependente grava estado inconsistente — e no caso
 * dos gatilhos, um estado que dispara para visitante REAL enquanto o
 * administrador ainda esta editando.
 */
import { computed, ref, watch, unref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { WIDGET_CONFIG_FIELDS, FIELD_BY_KEY } from './widgetConfigFields';

const clone = value =>
  value === null || typeof value !== 'object'
    ? value
    : JSON.parse(JSON.stringify(value));

const isEqual = (a, b) => {
  if (a === b) return true;
  if (a === null || b === null) return a === b;
  if (typeof a !== 'object' || typeof b !== 'object') return false;
  return JSON.stringify(a) === JSON.stringify(b);
};

const readAll = inbox =>
  Object.fromEntries(
    WIDGET_CONFIG_FIELDS.map(field => [field.key, clone(field.read(inbox))])
  );

/**
 * Nomeia o que mudou. Campo escalar vira `position`; campo de grupo vira uma
 * entrada por subcampo alterado (`appearance.position`), porque o dialogo de
 * troca de perfil e a barra de salvar precisam LISTAR nominalmente o que muda —
 * "3 alteracoes" sem dizer quais e a mesma opacidade que a tela existe para
 * corrigir.
 */
export const diffFields = (saved, draft) => {
  const changed = [];
  WIDGET_CONFIG_FIELDS.forEach(({ key, group }) => {
    const before = saved?.[key];
    const after = draft?.[key];
    if (isEqual(before, after)) return;

    if (!group) {
      changed.push(key);
      return;
    }

    const subKeys = new Set([
      ...Object.keys(before ?? {}),
      ...Object.keys(after ?? {}),
    ]);
    subKeys.forEach(subKey => {
      if (!isEqual(before?.[subKey], after?.[subKey])) {
        changed.push(`${key}.${subKey}`);
      }
    });
  });
  return changed;
};

/**
 * Monta o PATCH com o MINIMO que mudou. Um campo de grupo viaja inteiro (ver a
 * nota do merge raso em `widgetConfigFields.js`); os outros viajam sozinhos.
 */
export const buildPayload = (saved, draft) => {
  const payload = {};
  WIDGET_CONFIG_FIELDS.forEach(field => {
    if (isEqual(saved?.[field.key], draft?.[field.key])) return;
    const value = clone(draft[field.key]);

    if (field.scope === 'channel') {
      payload.channel = { ...(payload.channel ?? {}), [field.path]: value };
    } else if (field.scope === 'additional') {
      payload.additional_attributes = {
        ...(payload.additional_attributes ?? {}),
        [field.path]: value,
      };
    } else {
      payload[field.path] = value;
    }
  });
  return payload;
};

export function useInboxWidgetConfig(inboxId) {
  const store = useStore();

  const inbox = computed(() =>
    store.getters['inboxes/getInbox'](unref(inboxId))
  );
  const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

  const saved = ref(readAll(inbox.value));
  const draft = ref(readAll(inbox.value));
  const saveError = ref('');

  const dirtyFields = computed(() => diffFields(saved.value, draft.value));

  /**
   * O store so pode reescrever o rascunho quando NAO ha pendencia. Um refresh
   * de lista chegando por websocket no meio da edicao nao pode apagar o que o
   * administrador digitou.
   */
  watch(
    () => inbox.value,
    next => {
      const fresh = readAll(next);
      if (isEqual(saved.value, fresh)) return;
      const hadPendingEdits = dirtyFields.value.length > 0;
      saved.value = fresh;
      if (!hadPendingEdits) draft.value = clone(fresh);
    },
    { deep: true }
  );
  const dirtyCount = computed(() => dirtyFields.value.length);
  const isDirty = computed(() => dirtyCount.value > 0);
  const isSaving = computed(() => Boolean(uiFlags.value?.isUpdating));
  const isLoading = computed(() => Boolean(uiFlags.value?.isFetchingItem));

  const set = (key, value) => {
    if (!FIELD_BY_KEY[key]) {
      throw new Error(`[useInboxWidgetConfig] campo desconhecido: ${key}`);
    }
    draft.value = { ...draft.value, [key]: clone(value) };
  };

  /** Escreve UM subcampo de um grupo sem tocar nos irmaos. */
  const setIn = (key, subKey, value) => {
    const field = FIELD_BY_KEY[key];
    if (!field?.group) {
      throw new Error(`[useInboxWidgetConfig] ${key} nao e campo de grupo`);
    }
    set(key, { ...draft.value[key], [subKey]: clone(value) });
  };

  const discard = () => {
    draft.value = clone(saved.value);
    saveError.value = '';
  };

  const save = async () => {
    if (!isDirty.value) return { saved: false, payload: null };

    const payload = buildPayload(saved.value, draft.value);
    saveError.value = '';
    try {
      await store.dispatch('inboxes/updateInbox', {
        id: unref(inboxId),
        formData: false,
        ...payload,
      });
      saved.value = clone(draft.value);
      return { saved: true, payload };
    } catch (error) {
      // O toast some e o administrador que acabou de configurar dez campos fica
      // sem saber o que falhou: quem consome guarda isto numa faixa persistente.
      saveError.value = error?.message ?? '';
      throw error;
    }
  };

  return {
    inbox,
    draft,
    saved,
    isDirty,
    dirtyCount,
    dirtyFields,
    isSaving,
    isLoading,
    saveError,
    set,
    setIn,
    discard,
    save,
  };
}
