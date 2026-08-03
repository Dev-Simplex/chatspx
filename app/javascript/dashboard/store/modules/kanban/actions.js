import types from './mutation-types';
import KanbanAPI from '../../../api/kanban';

const DEFAULT_STAGE_PAGE_LIMIT = 30;
const DEFAULT_SCHEDULED_PAGE_LIMIT = 50;
const stageRequestLocks = new Map();
const scheduledRequestLocks = new Map();

// Prevê o topo da coluna para o movimento otimista não dar um segundo salto.
//
// NÃO é um espelho exato do `FunnelItem.top_position_for`: o backend tira o
// `min(position)` de TODAS as linhas da etapa, e aqui só temos as CARREGADAS (a
// página traz 30, ordenadas por recência — o mínimo real costuma estar fora).
// O número diverge de propósito; quem garante a ordem é o invariante do
// subconjunto: como o carregado ⊆ total, `min(total) ≤ min(carregado)`, então
// tanto esta previsão quanto o valor que o servidor devolve são MENORES que
// qualquer position visível — e o cartão aparece em primeiro nos dois casos
// (KanbanColumn ordena por position ASC).
//
// Ou seja: serve para ORDENAR, nunca como position exata (não mande este valor
// para o backend).
const topPositionForStage = (state, funnelId, stageId, excludingId) => {
  const stageKey = `${Number(funnelId)}:${Number(stageId)}`;
  const ids = state.stageItems?.[stageKey] || [];
  const positions = ids
    .filter(id => Number(id) !== Number(excludingId))
    .map(id => Number(state.funnelItems?.[id]?.position))
    .filter(Number.isFinite);

  return positions.length ? Math.min(...positions) - 1 : 1;
};

const defaultScheduledWindow = () => {
  const now = new Date();
  const past = new Date(now);
  past.setDate(past.getDate() - 30);
  past.setHours(0, 0, 0, 0);
  const future = new Date(now);
  future.setDate(future.getDate() + 30);
  future.setHours(23, 59, 59, 999);
  return {
    from: past.toISOString(),
    to: future.toISOString(),
  };
};

const resolveScheduledMessagesQuery = (payload, fallbackFilters = {}) => {
  const fallbackWindow = defaultScheduledWindow();

  if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
    const resolvedMode = Object.prototype.hasOwnProperty.call(payload, 'mode')
      ? payload.mode
      : 'cursor';

    return {
      mode: resolvedMode,
      conversationId:
        payload.conversationId ?? fallbackFilters.conversationId ?? null,
      status: payload.status || fallbackFilters.status || 'all',
      from: payload.from || fallbackFilters.from || fallbackWindow.from,
      to: payload.to || fallbackFilters.to || fallbackWindow.to,
      limit:
        payload.limit != null
          ? Number(payload.limit)
          : Number(fallbackFilters.limit || DEFAULT_SCHEDULED_PAGE_LIMIT),
      cursor: payload.cursor || null,
      append: Boolean(payload.append),
    };
  }

  return {
    conversationId: payload || null,
    mode: 'cursor',
    status: fallbackFilters.status || 'all',
    from: fallbackFilters.from || fallbackWindow.from,
    to: fallbackFilters.to || fallbackWindow.to,
    limit: Number(fallbackFilters.limit || DEFAULT_SCHEDULED_PAGE_LIMIT),
    cursor: null,
    append: false,
  };
};

const isResolvedStage = stage => {
  const automationType = stage?.automationType || stage?.automation_type;
  if (automationType === 'resolved') return true;
  const name = (stage?.name || '').toLowerCase();
  return name === 'resolved' || name === 'resolvido';
};

const shouldUseCursorLoading = ({ rootState, rootGetters }) => {
  const accountId = Number(rootState?.route?.params?.accountId);
  const featureGetter = rootGetters?.['accounts/isFeatureEnabledonAccount'];

  if (typeof featureGetter === 'function' && accountId) {
    return featureGetter(accountId, 'kanban_cursor_loading');
  }

  return true;
};

const shouldUseKanbanUxV2 = ({ rootState, rootGetters }) => {
  const accountId = Number(rootState?.route?.params?.accountId);
  const featureGetter = rootGetters?.['accounts/isFeatureEnabledonAccount'];

  if (typeof featureGetter === 'function' && accountId) {
    return featureGetter(accountId, 'kanban_ux_v2');
  }

  return true;
};

const parseStagePayload = response => {
  const data = response?.data;
  if (Array.isArray(data)) return data;
  if (data?.stages && Array.isArray(data.stages)) return data.stages;
  if (data?.funnel_stages && Array.isArray(data.funnel_stages)) {
    return data.funnel_stages;
  }
  return [];
};

const parseCursorResponse = (response, fallbackLimit) => {
  const data = response?.data;
  if (Array.isArray(data)) {
    return {
      items: data,
      meta: {
        hasMore: false,
        nextCursor: null,
        limit: fallbackLimit,
      },
    };
  }

  return {
    items: Array.isArray(data?.payload) ? data.payload : [],
    meta: {
      hasMore: Boolean(data?.meta?.has_more),
      nextCursor: data?.meta?.next_cursor || null,
      limit: Number(data?.meta?.limit || fallbackLimit),
      stageId: data?.meta?.stage_id,
      aggregates: data?.meta?.aggregates || {},
    },
  };
};

const parseScheduledResponse = (response, fallbackLimit) => {
  const data = response?.data;
  if (Array.isArray(data)) {
    return {
      items: data,
      meta: {
        hasMore: false,
        nextCursor: null,
        limit: fallbackLimit,
        status: 'all',
        from: null,
        to: null,
      },
    };
  }

  return {
    items: Array.isArray(data?.payload) ? data.payload : [],
    meta: {
      hasMore: Boolean(data?.meta?.has_more),
      nextCursor: data?.meta?.next_cursor || null,
      limit: Number(data?.meta?.limit || fallbackLimit),
      status: data?.meta?.status || 'all',
      from: data?.meta?.from || null,
      to: data?.meta?.to || null,
    },
  };
};

const defaultViewFilters = () => ({
  query: '',
  stageIds: [],
  labelIds: [],
  assigneeId: null,
  status: 'all',
});

const isViewBootstrapped = (viewBootstrap, view) => {
  if (view === 'kanban') return Boolean(viewBootstrap?.kanbanLoaded);
  if (view === 'list') return Boolean(viewBootstrap?.listLoaded);
  if (view === 'calendar') return Boolean(viewBootstrap?.calendarLoaded);
  return false;
};

const sanitizeStageQueue = stageIds => [
  ...new Set(
    (stageIds || []).map(id => Number(id)).filter(id => !Number.isNaN(id))
  ),
];

// ── Tempo real do board (plano task/kanban-tempo-real.md) ─────────────
//
// Invariantes de TODO handler remoto:
//   1. só reage ao funil que está na tela (`funnel_id === activeFunnelId`);
//   2. é IDEMPOTENTE (aplicar duas vezes = aplicar uma) — é isto, e não "quem
//      fez", que protege contra o eco da própria ação;
//   3. é best-effort: nunca lança para fora do websocket.
//
// ⚠️ NÃO volte a descartar evento por `performer.id === currentUserId`.
// Existia esse guard e ele quebrava o caso real de uma pessoa com o board aberto
// em DUAS janelas (ou desktop + notebook): o evento chegava e era jogado fora
// porque "fui eu quem fez", então a segunda janela nunca acompanhava — sintoma
// "atualiza uma vez e depois nunca mais". Quem faz a ação já aplicou o
// otimismo local, então o eco cai sozinho na guarda de idempotência (mesma
// etapa = no-op) sem precisar saber quem foi. O `performer` continua vindo no
// payload, mas só para dizer "movido por fulano" no destaque do card.
//
// Onde NÃO precisa de guarda:
//   • filtro da view — `viewFilters` é aplicado na RENDERIZAÇÃO
//     (`KanbanBoard.getFilteredItemsForStage` / `ListView`), não no store. Card
//     que não passa no filtro entra no cache e simplesmente não desenha; e volta
//     a aparecer sozinho quando o usuário limpa o filtro. Filtrar aqui deixaria
//     o cache mentindo para o resto da tela (contadores, busca, preview);
//   • dedupe por telefone — `assignItemToStage` (mutations.js) já espelha o
//     `deduplicate_by_contact_phone` do controller, inclusive o 9º dígito BR,
//     por etapa e resolvendo pelo mais recente. Inserir por aqui passa pelo
//     mesmo caminho.

// Um card do socket só é INSERÍVEL se vier com o que desenhar. Payload antigo
// (só ids, de uma VM ainda não deployada) cai fora e o card aparece no próximo
// load — o mesmo comportamento de antes, sem card-esqueleto na tela.
const isRenderableRemoteItem = data =>
  Boolean(data?.conversation || data?.title || data?.is_task);

// O envelope do broadcast carrega `account_id`/`performer` (metadado do
// transporte). Não são campos do card — ficam de fora do store.
const remoteItemPayload = data => {
  const { account_id: _accountId, performer: _performer, ...item } = data || {};
  return item;
};

// Quanto tempo o card fica destacado depois de mudar por ação remota. Casado
// com a animação de `.kanban-card--remote` em kanban-theme.css.
const REMOTE_HIGHLIGHT_MS = 2600;

export const actions = {
  async fetchFunnels({ commit }) {
    commit(types.SET_KANBAN_UI_FLAG, { isFetching: true });
    try {
      const response = await KanbanAPI.getFunnels();
      commit(types.SET_FUNNELS, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isFetching: false });
    }
  },

  async fetchFunnel({ commit }, funnelId) {
    commit(types.SET_KANBAN_UI_FLAG, { isFetching: true });
    try {
      const response = await KanbanAPI.getFunnel(funnelId);
      commit(types.SET_FUNNEL, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isFetching: false });
    }
  },

  async createFunnel({ commit }, data) {
    commit(types.SET_KANBAN_UI_FLAG, { isCreating: true });
    try {
      const response = await KanbanAPI.createFunnel(data);
      commit(types.ADD_FUNNEL, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isCreating: false });
    }
  },

  async updateFunnel({ commit }, { funnelId, data }) {
    commit(types.SET_KANBAN_UI_FLAG, { isUpdating: true });
    try {
      const response = await KanbanAPI.updateFunnel(funnelId, data);
      commit(types.UPDATE_FUNNEL, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isUpdating: false });
    }
  },

  // Fase 8: create a funnel from a template (returns the new funnel).
  async createFunnelFromTemplate({ commit }, data) {
    commit(types.SET_KANBAN_UI_FLAG, { isCreating: true });
    try {
      const response = await KanbanAPI.createFunnelFromTemplate(data);
      commit(types.ADD_FUNNEL, response.data);
      return response.data;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isCreating: false });
    }
  },

  async deleteFunnel({ commit }, funnelId) {
    commit(types.SET_KANBAN_UI_FLAG, { isDeleting: true });
    try {
      await KanbanAPI.deleteFunnel(funnelId);
      commit(types.DELETE_FUNNEL, funnelId);
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isDeleting: false });
    }
  },

  async reorderStages({ commit }, { funnelId, stageIds }) {
    await KanbanAPI.reorderStages(funnelId, stageIds);
    const response = await KanbanAPI.getFunnelStages(funnelId);
    commit(types.SET_FUNNEL_STAGES, {
      funnelId,
      stages: parseStagePayload(response),
    });
  },

  // ── Custom field definitions (Kanban v2 / Fase 2) ──────────────────
  async fetchCustomFields({ commit }, funnelId) {
    if (!funnelId) return [];
    const response = await KanbanAPI.getCustomFields(funnelId);
    const fields = Array.isArray(response.data) ? response.data : [];
    commit(types.SET_FUNNEL_CUSTOM_FIELDS, { funnelId, fields });
    return fields;
  },

  async createCustomField({ dispatch }, { funnelId, data }) {
    const response = await KanbanAPI.createCustomField(funnelId, data);
    await dispatch('fetchCustomFields', funnelId);
    return response.data;
  },

  async updateCustomField({ dispatch }, { funnelId, fieldId, data }) {
    const response = await KanbanAPI.updateCustomField(funnelId, fieldId, data);
    await dispatch('fetchCustomFields', funnelId);
    return response.data;
  },

  async deleteCustomField({ dispatch }, { funnelId, fieldId }) {
    await KanbanAPI.deleteCustomField(funnelId, fieldId);
    await dispatch('fetchCustomFields', funnelId);
  },

  // Update a card's custom field VALUES (merged server-side into the
  // conversation's custom_attributes; only this funnel's namespaced keys).
  async updateItemCustomAttributes(
    { commit },
    { funnelId, itemId, conversationId, attributes }
  ) {
    const response = await KanbanAPI.updateItemCustomAttributes(
      funnelId,
      itemId,
      attributes
    );
    const nextAttributes = response.data?.custom_attributes || {};
    commit(types.UPDATE_ITEM_CONVERSATION, {
      id: conversationId,
      patch: { custom_attributes: nextAttributes },
    });
    return nextAttributes;
  },

  // Patch pontual da conversa de um card no board (ex.: após "Assumir e
  // visualizar" atualizar o assignee sem recarregar o quadro).
  patchItemConversation(
    { commit },
    { displayId, id, patch, bumpRecency } = {}
  ) {
    if (!patch) return;
    commit(types.UPDATE_ITEM_CONVERSATION, {
      displayId,
      id,
      patch,
      bumpRecency,
    });
  },

  async fetchFunnelStages({ commit }, funnelId) {
    if (!funnelId) return { data: [] };

    const response = await KanbanAPI.getFunnelStages(funnelId);
    const stages = parseStagePayload(response);
    commit(types.SET_FUNNEL_STAGES, { funnelId, stages });
    return { data: stages };
  },

  async createStage({ commit }, { funnelId, data }) {
    const response = await KanbanAPI.createStage(funnelId, data);
    commit(types.ADD_FUNNEL_STAGE, response.data);
    return response;
  },

  async updateStage({ commit }, { funnelId, stageId, data }) {
    const response = await KanbanAPI.updateStage(funnelId, stageId, data);
    commit(types.UPDATE_FUNNEL_STAGE, {
      ...response.data,
      funnel_id: response.data?.funnel_id || funnelId,
    });
    return response;
  },

  async deleteStage({ commit }, { funnelId, stageId }) {
    await KanbanAPI.deleteStage(funnelId, stageId);
    commit(types.DELETE_FUNNEL_STAGE, { funnelId, stageId });
  },

  async fetchFunnelItemsPage(
    { commit, rootState, rootGetters, getters },
    {
      funnelId,
      stageId,
      excludeAutomationType,
      cursor = null,
      limit = DEFAULT_STAGE_PAGE_LIMIT,
      append = false,
    }
  ) {
    if (!funnelId || !stageId) {
      return { data: { payload: [], meta: {} } };
    }

    const requestKey = `${Number(funnelId)}:${Number(stageId)}`;
    const inFlightRequest = stageRequestLocks.get(requestKey);
    if (inFlightRequest) return inFlightRequest;

    const meta = getters.getStageMeta(funnelId, stageId);
    if (meta?.isLoading) return null;

    const requestPromise = (async () => {
      commit(types.SET_STAGE_META, {
        funnelId,
        stageId,
        meta: { isLoading: true, error: false },
      });

      try {
        const useCursor = shouldUseCursorLoading({ rootState, rootGetters });
        const options = {
          stageId,
          excludeAutomationType,
        };

        if (useCursor) {
          options.mode = 'cursor';
          options.limit = limit;
          options.cursor = cursor;
        }

        const response = await KanbanAPI.getFunnelItems(funnelId, options);
        const parsed = parseCursorResponse(response, limit);

        commit(types.UPSERT_STAGE_ITEMS, {
          funnelId,
          stageId,
          items: parsed.items,
          append,
        });
        commit(types.SET_STAGE_META, {
          funnelId,
          stageId,
          meta: {
            hasMore: parsed.meta.hasMore,
            nextCursor: parsed.meta.nextCursor,
            limit: parsed.meta.limit,
            loaded: true,
            isLoading: false,
            error: false,
            // Aggregates only arrive on the first page (cursor null); don't let
            // a "load more" response blank them out.
            ...(append ? {} : { aggregates: parsed.meta.aggregates || {} }),
          },
        });

        return response;
      } catch (error) {
        commit(types.SET_STAGE_META, {
          funnelId,
          stageId,
          meta: { isLoading: false, error: true },
        });
        throw error;
      } finally {
        stageRequestLocks.delete(requestKey);
      }
    })();

    stageRequestLocks.set(requestKey, requestPromise);
    return requestPromise;
  },

  async loadNextStagePage(
    { dispatch, getters },
    {
      funnelId,
      stageId,
      excludeAutomationType,
      limit = DEFAULT_STAGE_PAGE_LIMIT,
    }
  ) {
    const meta = getters.getStageMeta(funnelId, stageId);
    if (!meta?.hasMore || meta?.isLoading) return null;

    return dispatch('fetchFunnelItemsPage', {
      funnelId,
      stageId,
      excludeAutomationType,
      cursor: meta.nextCursor,
      limit,
      append: true,
    });
  },

  async bootstrapFunnel(
    { commit, getters, dispatch },
    {
      funnelId,
      excludeAutomationType = 'resolved',
      limit = DEFAULT_STAGE_PAGE_LIMIT,
      includeResolved = false,
    }
  ) {
    if (!funnelId) return;

    commit(types.SET_KANBAN_UI_FLAG, { isFetching: true });
    try {
      const stages = getters.getFunnelStages(funnelId);
      if (!Array.isArray(stages) || stages.length === 0) return;

      const stagesToLoad = includeResolved
        ? stages
        : stages.filter(stage => !isResolvedStage(stage));

      await Promise.all(
        stagesToLoad.map(stage =>
          dispatch('fetchFunnelItemsPage', {
            funnelId,
            stageId: stage.id,
            excludeAutomationType,
            limit,
            append: false,
          })
        )
      );
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isFetching: false });
    }
  },

  async fetchFunnelItems(
    { dispatch, getters, commit },
    {
      funnelId,
      stageId = null,
      excludeAutomationType,
      page = null,
      perPage = null,
      merge = false,
    }
  ) {
    if (!funnelId) return { data: [] };

    if (page != null || perPage != null) {
      const response = await KanbanAPI.getFunnelItems(funnelId, {
        stageId,
        excludeAutomationType,
        page,
        perPage,
      });
      const items = Array.isArray(response.data) ? response.data : [];
      if (stageId) {
        commit(types.UPSERT_STAGE_ITEMS, {
          funnelId,
          stageId,
          items,
          append: merge,
        });
        commit(types.SET_STAGE_META, {
          funnelId,
          stageId,
          meta: {
            hasMore: items.length >= (perPage || DEFAULT_STAGE_PAGE_LIMIT),
            nextCursor: null,
            limit: perPage || DEFAULT_STAGE_PAGE_LIMIT,
            loaded: true,
            isLoading: false,
            error: false,
          },
        });
      } else {
        commit(
          merge ? types.MERGE_FUNNEL_ITEMS : types.SET_FUNNEL_ITEMS,
          items
        );
      }
      return { ...response, data: items };
    }

    if (stageId) {
      const meta = getters.getStageMeta(funnelId, stageId);
      return dispatch('fetchFunnelItemsPage', {
        funnelId,
        stageId,
        excludeAutomationType,
        cursor: merge ? meta?.nextCursor : null,
        limit: perPage || DEFAULT_STAGE_PAGE_LIMIT,
        append: merge,
      });
    }

    await dispatch('bootstrapFunnel', {
      funnelId,
      excludeAutomationType,
      limit: perPage || DEFAULT_STAGE_PAGE_LIMIT,
      includeResolved: !excludeAutomationType,
    });
    return { data: [] };
  },

  async createItem({ commit }, { funnelId, data }) {
    const response = await KanbanAPI.createItem(funnelId, data);
    commit(types.ADD_FUNNEL_ITEM, response.data);
    return response;
  },

  async updateItem({ commit }, { funnelId, itemId, data }) {
    const response = await KanbanAPI.updateItem(funnelId, itemId, data);
    commit(types.UPDATE_FUNNEL_ITEM, response.data);
    return response;
  },

  // Arrastar um cartão de uma etapa para outra. Otimista pelo mesmo motivo do
  // `reorderItems`: a lista do draggable é one-way, então esperar o PATCH fazia
  // o card VOLTAR para a coluna de origem e só pular depois da resposta —
  // medido em 0,26s a 1,63s no staging. Move na hora e reverte se o backend
  // recusar (o servidor continua sendo a autoridade: a resposta é reaplicada).
  async moveItemToStage({ commit, state }, { funnelId, itemId, stageId }) {
    const id = Number(itemId);
    const nextStageId = Number(stageId);
    const current = state.funnelItems[id];
    if (!current || !nextStageId) return null;

    const previousStageId = Number(
      current.funnelStageId ?? current.funnel_stage_id
    );
    if (previousStageId === nextStageId) return null;

    // Só camelCase: a mutação camelizes o que recebe, e misturar as duas grafias
    // da MESMA chave deixaria a vencedora por conta da ordem do merge.
    // A `position` espelha o `FunnelItem.top_position_for` do backend (cartão que
    // chega vai para o topo). Sem prever isso o card cairia no meio da coluna e
    // pularia DE NOVO ao chegar a resposta — troca um salto por dois.
    commit(types.UPDATE_FUNNEL_ITEM, {
      ...current,
      funnelStageId: nextStageId,
      position: topPositionForStage(state, funnelId, nextStageId, id),
    });

    try {
      const response = await KanbanAPI.updateItem(funnelId, id, {
        funnel_stage_id: nextStageId,
      });
      commit(types.UPDATE_FUNNEL_ITEM, response.data);
      return response;
    } catch (error) {
      commit(types.UPDATE_FUNNEL_ITEM, {
        ...current,
        funnelStageId: previousStageId,
      });
      throw error;
    }
  },

  async deleteItem({ commit }, { funnelId, itemId }) {
    await KanbanAPI.deleteItem(funnelId, itemId);
    commit(types.DELETE_FUNNEL_ITEM, itemId);
  },

  // Reordenação manual de cartões dentro de uma coluna (Kanban DB restructure / P1).
  // Atualiza `position` otimisticamente (a lista do draggable é one-way: sem isso o
  // card volta pro lugar) e persiste no backend; reverte as posições em caso de erro.
  async reorderItems({ commit, state }, { funnelId, stageId, itemIds }) {
    const ids = (itemIds || []).map(Number).filter(id => !Number.isNaN(id));
    if (!ids.length) return;

    const previous = ids.map(id => ({
      id,
      position: state.funnelItems[id]?.position,
    }));
    const next = ids.map((id, index) => ({ id, position: index + 1 }));

    commit(types.SET_FUNNEL_ITEM_POSITIONS, { positions: next });
    try {
      await KanbanAPI.reorderItems(funnelId, stageId, ids);
    } catch (error) {
      commit(types.SET_FUNNEL_ITEM_POSITIONS, { positions: previous });
      throw error;
    }
  },

  // Bridges the central websocket events to the kanban store so cards reflect
  // status/assignee/priority/labels/new-message changes in real time without a
  // full reload. Self-protecting: bails out cheaply when the board is inactive
  // or the payload is unusable, and never touches stage placement (the realtime
  // conversation payload carries no funnel_stage_id).
  syncConversationFromRealtime({ state, commit }, data) {
    try {
      if (!state?.activeFunnelId) return;
      if (!data || typeof data !== 'object') return;

      const displayId = data?.conversation_id ?? data?.id;
      if (displayId == null || displayId === '') return;

      const patch = {};

      // message.created carries the message itself, not a conversation object.
      const isMessageCreated =
        data?.message_type !== undefined &&
        (data?.content !== undefined || data?.created_at !== undefined);

      if (data?.status !== undefined) {
        patch.status = data.status;
      }

      const hasAssignee =
        data?.assignee_id !== undefined ||
        data?.meta?.assignee !== undefined ||
        data?.meta?.assignee?.id !== undefined;
      if (hasAssignee) {
        patch.assigneeId =
          data?.assignee_id ?? data?.meta?.assignee?.id ?? null;
        if (data?.meta?.assignee !== undefined) {
          patch.meta = {
            ...(data?.meta || {}),
            assignee: data?.meta?.assignee ?? null,
          };
        }
      }

      if (data?.priority !== undefined) {
        patch.priority = data.priority;
      }

      if (data?.labels !== undefined) {
        patch.labels = data.labels;
      }

      let bumpRecency = false;

      if (isMessageCreated) {
        const lastActivityAt =
          data?.conversation?.last_activity_at ?? data?.created_at;
        if (lastActivityAt !== undefined && lastActivityAt !== null) {
          patch.lastActivityAt = lastActivityAt;
        }
        if (data?.content !== undefined || data?.created_at !== undefined) {
          patch.lastMessage = {
            content: data?.content,
            created_at: data?.created_at,
          };
        }
        bumpRecency = true;
      } else if (data?.last_activity_at !== undefined) {
        patch.lastActivityAt = data.last_activity_at;
      }

      if (Object.keys(patch).length === 0) return;

      commit(types.UPDATE_ITEM_CONVERSATION, {
        displayId,
        // For message.created, data.id is the MESSAGE id (not a conversation
        // id) — don't let the numeric fallback match an unrelated card.
        id: isMessageCreated ? null : data?.id,
        patch,
        bumpRecency,
      });
    } catch (error) {
      // Realtime sync is best-effort; never let it break websocket handling.
    }
  },

  async bulkMoveItems({ dispatch }, { funnelId, conversationIds, stageId }) {
    await KanbanAPI.bulkMoveItems(funnelId, conversationIds, stageId);
    await dispatch('bootstrapFunnel', {
      funnelId,
      excludeAutomationType: 'resolved',
      limit: DEFAULT_STAGE_PAGE_LIMIT,
    });
  },

  // Bulk reassign / tag / archive (Fase 3) — refresh the funnel afterwards.
  async bulkUpdateItems(
    { dispatch },
    { funnelId, conversationIds, operation, assigneeId, labels }
  ) {
    const response = await KanbanAPI.bulkUpdateItems(funnelId, {
      operation,
      conversation_ids: conversationIds,
      assignee_id: assigneeId,
      labels,
    });
    await dispatch('bootstrapFunnel', {
      funnelId,
      excludeAutomationType: 'resolved',
      limit: DEFAULT_STAGE_PAGE_LIMIT,
    });
    return response.data;
  },

  // ── Saved views (Fase 3) ───────────────────────────────────────────
  async fetchSavedViews({ commit }, funnelId) {
    const response = await KanbanAPI.getFunnelViews(funnelId);
    const views = Array.isArray(response.data) ? response.data : [];
    commit(types.SET_SAVED_VIEWS, views);
    return views;
  },

  async createSavedView({ commit }, data) {
    const response = await KanbanAPI.createFunnelView(data);
    commit(types.ADD_SAVED_VIEW, response.data);
    return response.data;
  },

  async updateSavedView({ commit }, { viewId, data }) {
    const response = await KanbanAPI.updateFunnelView(viewId, data);
    commit(types.UPDATE_SAVED_VIEW, response.data);
    return response.data;
  },

  async deleteSavedView({ commit }, viewId) {
    await KanbanAPI.deleteFunnelView(viewId);
    commit(types.DELETE_SAVED_VIEW, viewId);
  },

  // Apply a saved view: restore its filters and view mode.
  applySavedView({ commit }, view) {
    if (!view) return;
    commit(types.SET_VIEW_FILTERS, view.filters || {});
    if (view.view_mode) commit(types.SET_VIEW_MODE, view.view_mode);
  },

  // Tempo real: outra pessoa moveu um card. Reloca a cópia local — ou INSERE,
  // quando não temos o card.
  //
  // O `return` no card desconhecido era a causa nº 1 do "só o F5 resolve": com
  // `kanban_cursor_loading` ligado cada coluna carrega uma página, então o
  // receptor quase nunca tem o card que estava lá embaixo, e o evento era
  // descartado em silêncio. Agora o payload vem completo (FunnelItem#push_event_data)
  // e o card entra desenhado.
  applyRemoteMove({ state, commit, dispatch }, data) {
    try {
      if (!data || typeof data !== 'object') return;
      // Only react when this board is showing the affected funnel.
      if (Number(data.funnel_id) !== Number(state.activeFunnelId)) return;

      const targetStage = Number(data.funnel_stage_id);
      if (!targetStage) return;

      const existing = state.funnelItems[data.id];
      if (!existing) {
        if (!isRenderableRemoteItem(data)) return;
        // Idempotente: `assignItemToStage` reinsere o mesmo id no mesmo lugar.
        commit(types.ADD_FUNNEL_ITEM, remoteItemPayload(data));
        dispatch('flagRemoteActivity', {
          itemId: data.id,
          performer: data.performer,
        });
        return;
      }

      // ESTA é a guarda contra o eco da própria ação: quem arrastou já aplicou o
      // movimento otimista, então o evento chega com a etapa que o card já tem e
      // vira no-op (sem o segundo salto na tela). Quem NÃO arrastou — inclusive
      // a outra janela da mesma pessoa — ainda está na etapa antiga e aplica.
      const currentStage = Number(
        existing.funnelStageId ?? existing.funnel_stage_id
      );
      if (targetStage === currentStage) return;

      // Last-write-wins: ignore an out-of-order older move.
      const localMovedAt = existing.movedAt ?? existing.moved_at;
      if (
        localMovedAt &&
        data.moved_at &&
        new Date(localMovedAt) > new Date(data.moved_at)
      ) {
        return;
      }

      // Preserva o que já temos (ex.: `lastMessage`, que não vem no broadcast) e
      // só reloca. `position` vem do backend para o card cair no topo da coluna
      // de destino, igual ao que quem arrastou está vendo.
      commit(types.UPDATE_FUNNEL_ITEM, {
        ...existing,
        funnel_stage_id: targetStage,
        funnelStageId: targetStage,
        moved_at: data.moved_at,
        movedAt: data.moved_at,
        ...(data.position == null ? {} : { position: Number(data.position) }),
      });
      dispatch('flagRemoteActivity', {
        itemId: data.id,
        performer: data.performer,
      });
    } catch (_) {
      // Real-time is best-effort; never throw out of a websocket handler.
    }
  },

  // Tempo real (Fase 2.1): cartão de TAREFA criado por outra pessoa.
  // Card de conversa NÃO passa por aqui — ele nasce pelo MoveService, que já
  // dispara `funnel_item.moved`, e o `applyRemoteMove` insere. A assimetria é
  // de propósito: os dois eventos juntos inseririam o card duas vezes.
  applyRemoteCreate({ state, commit, dispatch }, data) {
    try {
      if (!data || typeof data !== 'object') return;
      if (Number(data.funnel_id) !== Number(state.activeFunnelId)) return;
      if (!isRenderableRemoteItem(data)) return;

      // Idempotente: `assignItemToStage` faz upsert pelo id.
      commit(types.ADD_FUNNEL_ITEM, remoteItemPayload(data));
      dispatch('flagRemoteActivity', {
        itemId: data.id,
        performer: data.performer,
      });
    } catch (_) {
      // best-effort
    }
  },

  // Tempo real (Fase 2.2): card apagado por outra pessoa. Sem isto ele virava
  // fantasma — sumia para quem apagou e continuava clicável (404) para o resto.
  applyRemoteDelete({ state, commit }, data) {
    try {
      if (!data || typeof data !== 'object') return;
      if (Number(data.funnel_id) !== Number(state.activeFunnelId)) return;

      const itemId = Number(data.id);
      if (!itemId) return;
      // Idempotente: apagar o que já não existe é no-op na mutation.
      commit(types.DELETE_FUNNEL_ITEM, itemId);
    } catch (_) {
      // best-effort
    }
  },

  // Tempo real (Fase 2.3): UM evento para o bulk move inteiro. Cada item é
  // aplicado pelo mesmo caminho do move solto (insere ou reloca, idempotente);
  // acima do teto do backend vem `refetch: true` e recarregamos só as colunas
  // afetadas, em vez de receber um payload gigante pelo websocket.
  async applyRemoteBulk({ state, dispatch }, data) {
    try {
      if (!data || typeof data !== 'object') return;
      const funnelId = Number(data.funnel_id);
      if (funnelId !== Number(state.activeFunnelId)) return;

      if (data.refetch) {
        const stageIds = sanitizeStageQueue(data.stage_ids);
        await Promise.all(
          stageIds.map(stageId =>
            dispatch('fetchFunnelItemsPage', {
              funnelId,
              stageId,
              excludeAutomationType: 'resolved',
              append: false,
            })
          )
        );
        return;
      }

      // `performer` viaja junto para o destaque do card dizer quem moveu (o
      // eco da própria ação já foi descartado acima, então ele nunca sou eu).
      (data.items || []).forEach(item =>
        dispatch('applyRemoteMove', { ...item, performer: data.performer })
      );
    } catch (_) {
      // best-effort
    }
  },

  // Tempo real (Fase 3): outra pessoa reordenou os cards dentro de uma coluna.
  // Reusa a MESMA mutação do otimismo local (`reorderItems`), então a ordem
  // converge sem o card "pular" para quem arrastou.
  applyRemoteReorder({ state, commit }, data) {
    try {
      if (!data || typeof data !== 'object') return;
      if (Number(data.funnel_id) !== Number(state.activeFunnelId)) return;

      // Ignora ids que não temos: reorder de card desconhecido não justifica
      // refetch (ele chega completo no próximo load ou num move).
      const positions = (data.positions || [])
        .map(entry => ({
          id: Number(entry?.id),
          position: Number(entry?.position),
        }))
        .filter(
          entry =>
            entry.id &&
            Number.isFinite(entry.position) &&
            state.funnelItems?.[entry.id]
        );
      if (!positions.length) return;

      // Idempotente: gravar a mesma position duas vezes é o mesmo estado.
      commit(types.SET_FUNNEL_ITEM_POSITIONS, { positions });
    } catch (_) {
      // best-effort
    }
  },

  // Tempo real (Fase 5.2): marca o card que acabou de mudar por ação de outra
  // pessoa, para o KanbanCard piscar e mostrar "movido por {nome}". Sem isto o
  // card teleporta sem explicação e o colega acha que bugou (ou desfaz o move
  // do outro por cima).
  //
  // `performer` vem de graça do broadcast, MAS é nil quando o move veio de job
  // (automação, SLA, backfill) — `Current.user` só existe no request. Nesse caso
  // o card diz "movido automaticamente".
  flagRemoteActivity({ commit }, { itemId, performer } = {}) {
    const id = Number(itemId);
    if (!id) return;

    commit(types.SET_REMOTE_ACTIVITY, {
      itemId: id,
      name: performer?.name || null,
      automated: !performer?.id,
    });
    setTimeout(
      () => commit(types.CLEAR_REMOTE_ACTIVITY, id),
      REMOTE_HIGHLIGHT_MS
    );
  },

  // Tempo real (Fase 4): as colunas do funil mudaram. Evento grosso e
  // idempotente — recebemos a lista completa e ordenada, então não há ordem de
  // chegada nem estado parcial para gerenciar.
  //
  // Dois cuidados que o `SET_FUNNEL_STAGES` sozinho não cobre:
  //   • cards órfãos: a mutação troca o mapa de colunas, mas os cards da coluna
  //     apagada continuariam no store (no banco eles já foram — FunnelStage
  //     has_many :funnel_items, dependent: :destroy);
  //   • tela vazia: se o filtro de coluna apontava para a coluna que sumiu, o
  //     board ficaria sem nada e parecendo travado.
  applyRemoteStages({ state, commit }, data) {
    try {
      if (!data || typeof data !== 'object') return;
      const funnelId = Number(data.funnel_id);
      if (funnelId !== Number(state.activeFunnelId)) return;

      const stages = Array.isArray(data.stages) ? data.stages : [];
      const nextIds = new Set(stages.map(stage => Number(stage?.id)));

      const removedIds = Object.keys(state.funnelStages?.[funnelId] || {})
        .map(Number)
        .filter(stageId => !nextIds.has(stageId));
      removedIds.forEach(stageId =>
        commit(types.DELETE_FUNNEL_STAGE, { funnelId, stageId })
      );

      commit(types.SET_FUNNEL_STAGES, { funnelId, stages });

      if (!removedIds.length) return;

      const activeStageFilter = state.viewFilters?.stageIds || [];
      const survivingFilter = activeStageFilter.filter(stageId =>
        nextIds.has(Number(stageId))
      );
      if (survivingFilter.length !== activeStageFilter.length) {
        commit(types.SET_VIEW_FILTERS, { stageIds: survivingFilter });
      }
    } catch (_) {
      // best-effort
    }
  },

  setViewFilters({ commit }, filters = {}) {
    commit(types.SET_VIEW_FILTERS, filters);
  },

  resetViewFilters({ commit }) {
    commit(types.RESET_VIEW_FILTERS);
  },

  resetViewBootstrap({ commit }) {
    commit(types.RESET_VIEW_BOOTSTRAP);
  },

  async bootstrapListView(
    { commit, dispatch, getters },
    { funnelId, force = false, limit = 15 } = {}
  ) {
    if (!funnelId) return;

    const stages = getters
      .getFunnelStages(funnelId)
      .filter(stage => !isResolvedStage(stage));
    if (!stages.length) {
      commit(types.SET_VIEW_BOOTSTRAP, {
        listLoaded: true,
        listQueueStageIds: [],
      });
      return;
    }

    const stageIds = stages.map(stage => Number(stage.id)).filter(Boolean);

    if (force || !getters.getViewBootstrap?.listLoaded) {
      await Promise.all(
        stageIds.map(stageId =>
          dispatch('fetchFunnelItemsPage', {
            funnelId,
            stageId,
            excludeAutomationType: 'resolved',
            limit,
            append: false,
          })
        )
      );
    }

    const queue = sanitizeStageQueue(
      stageIds.filter(
        stageId => getters.getStageMeta(funnelId, stageId)?.hasMore
      )
    );

    commit(types.SET_VIEW_BOOTSTRAP, {
      listLoaded: true,
      listQueueStageIds: queue,
    });
  },

  async loadMoreListQueue(
    { commit, dispatch, getters },
    { funnelId, limit = 15 } = {}
  ) {
    if (!funnelId) return null;

    const currentQueue = sanitizeStageQueue(
      getters.getViewBootstrap?.listQueueStageIds || []
    );
    if (!currentQueue.length) return null;

    const stageId = currentQueue[0];
    await dispatch('loadNextStagePage', {
      funnelId,
      stageId,
      excludeAutomationType: 'resolved',
      limit,
    });

    const stageMeta = getters.getStageMeta(funnelId, stageId);
    const nextQueue = stageMeta?.hasMore
      ? [...currentQueue.slice(1), stageId]
      : currentQueue.slice(1);

    commit(types.SET_VIEW_BOOTSTRAP, {
      listQueueStageIds: sanitizeStageQueue(nextQueue),
    });

    return stageId;
  },

  async bootstrapView(
    { commit, dispatch, getters },
    { view, funnelId, force = false } = {}
  ) {
    if (!funnelId) return;
    const viewName = view || getters.getViewMode;
    if (!viewName) return;

    const alreadyLoaded = isViewBootstrapped(
      getters.getViewBootstrap,
      viewName
    );
    if (alreadyLoaded && !force) return;

    if (viewName === 'kanban') {
      await dispatch('bootstrapFunnel', {
        funnelId,
        excludeAutomationType: 'resolved',
      });
      commit(types.SET_VIEW_BOOTSTRAP, { kanbanLoaded: true });
      return;
    }

    if (viewName === 'list') {
      await dispatch('bootstrapListView', {
        funnelId,
        force,
      });
      return;
    }

    if (viewName === 'calendar') {
      await dispatch('bootstrapScheduledTimeline', {
        status: 'all',
      });
      commit(types.SET_VIEW_BOOTSTRAP, { calendarLoaded: true });
      return;
    }

    if (viewName === 'dashboard') {
      // Stats are cheap and should be fresh — always re-fetch on entry.
      await dispatch('fetchFunnelStats', { funnelId });
    }
  },

  // Dashboard live stats (Fase 6).
  async fetchFunnelStats({ commit }, { funnelId } = {}) {
    if (!funnelId) return null;
    const response = await KanbanAPI.getFunnelStats(funnelId);
    commit(types.SET_FUNNEL_STATS, { funnelId, stats: response.data });
    return response.data;
  },

  async fetchScheduledMessagesPage(
    { commit, getters, rootState, rootGetters },
    payload = null
  ) {
    const uiFlags = getters.getUIFlags || {};
    if (uiFlags.isCreating || uiFlags.isUpdating) {
      return { data: { payload: [], meta: {} } };
    }

    const currentFilters = getters.getScheduledFilters || {};
    const query = resolveScheduledMessagesQuery(payload, currentFilters);
    const useKanbanUxV2 = shouldUseKanbanUxV2({ rootState, rootGetters });
    const requestedMode =
      query.mode === undefined ? 'cursor' : query.mode || null;
    const effectiveMode = useKanbanUxV2 ? requestedMode || 'cursor' : null;
    const requestKey = JSON.stringify({
      mode: effectiveMode,
      status: query.status,
      from: query.from,
      to: query.to,
      limit: query.limit,
      cursor: query.cursor,
      conversationId: query.conversationId,
      append: query.append,
    });

    const inFlightRequest = scheduledRequestLocks.get(requestKey);
    if (inFlightRequest) return inFlightRequest;

    const requestPromise = (async () => {
      commit(types.SET_KANBAN_UI_FLAG, { isFetchingScheduledMessages: true });

      if (!query.append) {
        commit(types.SET_SCHEDULED_FILTERS, {
          status: query.status,
          conversationId: query.conversationId,
          from: query.from,
          to: query.to,
          limit: query.limit,
        });
      }

      try {
        const response = await KanbanAPI.getScheduledMessages({
          mode: effectiveMode,
          status: query.status,
          from: query.from,
          to: query.to,
          limit: query.limit,
          cursor: query.cursor,
          conversationId: query.conversationId,
        });

        const parsed = parseScheduledResponse(response, query.limit);
        commit(types.UPSERT_SCHEDULED_MESSAGES_PAGE, {
          messages: parsed.items,
          append: query.append,
        });
        commit(types.SET_SCHEDULED_META, {
          hasMore: parsed.meta.hasMore,
          nextCursor: parsed.meta.nextCursor,
          limit: parsed.meta.limit,
          loaded: true,
          error: false,
          status: parsed.meta.status,
          from: parsed.meta.from || query.from,
          to: parsed.meta.to || query.to,
        });
        commit(types.SET_SCHEDULED_UI, { lastFetchedAt: Date.now() });
        return response;
      } catch (error) {
        commit(types.SET_SCHEDULED_META, { loaded: true, error: true });
        return { data: { payload: [], meta: {} } };
      } finally {
        commit(types.SET_KANBAN_UI_FLAG, {
          isFetchingScheduledMessages: false,
        });
        scheduledRequestLocks.delete(requestKey);
      }
    })();

    scheduledRequestLocks.set(requestKey, requestPromise);
    return requestPromise;
  },

  async bootstrapScheduledTimeline({ dispatch }, payload = null) {
    return dispatch('fetchScheduledMessagesPage', {
      ...resolveScheduledMessagesQuery(payload),
      append: false,
      cursor: null,
    });
  },

  async loadMoreScheduledMessages({ dispatch, getters }, payload = {}) {
    const meta = getters.getScheduledMeta;
    if (!meta?.hasMore || !meta?.nextCursor) return null;

    const filters = getters.getScheduledFilters;
    return dispatch('fetchScheduledMessagesPage', {
      ...filters,
      ...payload,
      limit: payload?.limit || meta.limit || DEFAULT_SCHEDULED_PAGE_LIMIT,
      cursor: meta.nextCursor,
      append: true,
    });
  },

  async refreshPendingStatuses({ dispatch, getters }, payload = {}) {
    const filters = getters.getScheduledFilters;
    return dispatch('fetchScheduledMessagesPage', {
      ...filters,
      ...payload,
      cursor: null,
      append: false,
    });
  },

  async fetchScheduledMessages({ dispatch, getters }, payload = null) {
    const filters = getters.getScheduledFilters;
    const query = resolveScheduledMessagesQuery(payload, filters);
    return dispatch('fetchScheduledMessagesPage', {
      ...query,
      mode: query.mode || 'cursor',
      append: false,
      cursor: null,
    });
  },

  async createScheduledMessage({ commit }, data) {
    commit(types.SET_KANBAN_UI_FLAG, { isCreating: true });
    try {
      const response = await KanbanAPI.createScheduledMessage(data);
      commit(types.ADD_SCHEDULED_MESSAGE, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isCreating: false });
    }
  },

  async updateScheduledMessage({ commit }, { messageId, data }) {
    commit(types.SET_KANBAN_UI_FLAG, { isUpdating: true });
    try {
      const response = await KanbanAPI.updateScheduledMessage(messageId, data);
      commit(types.UPDATE_SCHEDULED_MESSAGE, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isUpdating: false });
    }
  },

  async deleteScheduledMessage({ commit }, messageId) {
    commit(types.SET_KANBAN_UI_FLAG, { isDeleting: true });
    try {
      await KanbanAPI.deleteScheduledMessage(messageId);
      commit(types.DELETE_SCHEDULED_MESSAGE, messageId);
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isDeleting: false });
    }
  },

  async fetchWahaInboxes({ commit }) {
    const response = await KanbanAPI.getWahaInboxes();
    const data = response?.data;
    const inboxes = Array.isArray(data) ? data : data?.payload || [];
    commit(types.SET_WAHA_INBOXES, inboxes);
    return { ...response, data: inboxes };
  },

  setActiveFunnelId({ commit }, funnelId) {
    commit(types.SET_ACTIVE_FUNNEL_ID, funnelId);
    commit(types.RESET_VIEW_BOOTSTRAP);
    commit(types.SET_VIEW_FILTERS, {
      ...defaultViewFilters(),
    });
  },

  setViewMode({ commit }, mode) {
    commit(types.SET_VIEW_MODE, mode);
  },
};
