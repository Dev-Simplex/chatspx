// Pinia store novo para o Kanban (P1-04).
// State normalizado. Coexiste com Vuex `kanban/` (consumidores legacy seguem
// usando-o). Componentes redesenhados (P1-01+, P1-08+) consomem este.
//
// Estruturas:
// - kanbans / stages / items: Record<id, entity>
// - stageIds[kanbanId]: ordem das stages
// - itemIdsByStage[stageId]: ordem dos itens
// - stageMeta[stageId]: paginação/loading
// - activeKanbanId / activeCardId / selectedItemIds
//
// Real-time (P1-13): applyRemoteEvent muta state sem refetch e respeita
// Lamport seq via useKanbanRealtimeStore.lastSeq.

import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import KanbanAPI from 'dashboard/api/kanban';

const STAGE_PAGE_LIMIT = 30;

const normalizeEntity = entity =>
  entity ? camelcaseKeys(entity, { deep: true }) : entity;

const sortByPosition = (a, b) => {
  const posA = a.position ?? 0;
  const posB = b.position ?? 0;
  if (posA !== posB) return posA - posB;
  const ca = new Date(a.createdAt || a.created_at || 0).getTime() || 0;
  const cb = new Date(b.createdAt || b.created_at || 0).getTime() || 0;
  return ca - cb;
};

export const useKanbanBoardStore = defineStore('kanbanBoard', {
  state: () => ({
    kanbans: {},
    stages: {},
    items: {},
    stageIds: {},
    itemIdsByStage: {},
    stageMeta: {},
    activeKanbanId: null,
    activeCardId: null,
    selectedItemIds: [],
    // P3-03: template confirmation modal trigger
    pendingTemplateConfirm: null,
    // P3-08: pending WIP override confirmation
    pendingWipOverride: null,
    uiFlags: {
      isFetchingKanbans: false,
      isFetchingKanban: false,
      isCreatingItem: false,
      isMovingItem: false,
    },
  }),

  getters: {
    kanbanList: state =>
      Object.values(state.kanbans).sort((a, b) => {
        // default (teamId null) primeiro, depois por position/createdAt
        const aDefault = a.teamId == null;
        const bDefault = b.teamId == null;
        if (aDefault !== bDefault) return aDefault ? -1 : 1;
        return sortByPosition(a, b);
      }),

    activeKanban: state =>
      state.activeKanbanId ? state.kanbans[state.activeKanbanId] : null,

    stagesOf: state => kanbanId => {
      const ids = state.stageIds[kanbanId] || [];
      return ids.map(id => state.stages[id]).filter(Boolean);
    },

    itemsOfStage: state => stageId => {
      const ids = state.itemIdsByStage[stageId] || [];
      return ids.map(id => state.items[id]).filter(Boolean);
    },

    itemById: state => id => state.items[id] || null,
    stageById: state => id => state.stages[id] || null,

    countByStage: state => stageId =>
      (state.itemIdsByStage[stageId] || []).length,

    stageMetaOf: state => stageId =>
      state.stageMeta[stageId] || {
        hasMore: false,
        nextCursor: null,
        isLoading: false,
        loaded: false,
      },
  },

  actions: {
    // ---------- helpers internos ----------
    upsertKanban(kanban) {
      const k = normalizeEntity(kanban);
      this.kanbans[k.id] = { ...this.kanbans[k.id], ...k };
    },

    upsertStage(stage) {
      const s = normalizeEntity(stage);
      this.stages[s.id] = { ...this.stages[s.id], ...s };
    },

    upsertItem(item) {
      const i = normalizeEntity(item);
      this.items[i.id] = { ...this.items[i.id], ...i };
    },

    setStageOrder(kanbanId, ids) {
      this.stageIds[kanbanId] = ids.map(Number);
    },

    setItemsOrder(stageId, ids) {
      this.itemIdsByStage[stageId] = ids.map(Number);
    },

    appendItemToStage(stageId, itemId, position = null) {
      const list = this.itemIdsByStage[stageId] || [];
      if (list.includes(itemId)) return;
      if (position == null) {
        this.itemIdsByStage[stageId] = [...list, itemId];
      } else {
        const next = [...list];
        next.splice(position, 0, itemId);
        this.itemIdsByStage[stageId] = next;
      }
    },

    removeItemFromStage(stageId, itemId) {
      const list = this.itemIdsByStage[stageId];
      if (!list) return;
      this.itemIdsByStage[stageId] = list.filter(id => id !== itemId);
    },

    // ---------- fetch ----------
    async fetchKanbans() {
      this.uiFlags.isFetchingKanbans = true;
      try {
        const { data } = await KanbanAPI.getFunnels();
        const list = Array.isArray(data) ? data : data?.kanbans || [];
        list.forEach(k => this.upsertKanban(k));
        return this.kanbanList;
      } finally {
        this.uiFlags.isFetchingKanbans = false;
      }
    },

    async fetchKanban(kanbanId) {
      if (!kanbanId) return null;
      this.uiFlags.isFetchingKanban = true;
      this.activeKanbanId = Number(kanbanId);
      try {
        const { data } = await KanbanAPI.getFunnel(kanbanId);
        const kanban = normalizeEntity(data);
        this.upsertKanban(kanban);

        // stages
        const stagesResp = await KanbanAPI.getFunnelStages(kanbanId);
        const stages = Array.isArray(stagesResp.data)
          ? stagesResp.data
          : stagesResp.data?.stages || [];
        const stagesSorted = stages.map(normalizeEntity).sort(sortByPosition);
        stagesSorted.forEach(s => this.upsertStage(s));
        this.setStageOrder(
          kanbanId,
          stagesSorted.map(s => s.id)
        );

        // primeira página de items por stage (eager primeiras 3, lazy resto)
        const eagerLimit = 3;
        await Promise.all(
          stagesSorted
            .slice(0, eagerLimit)
            .map(s => this.fetchStageItems(kanbanId, s.id, { reset: true }))
        );

        return this.kanbans[kanbanId];
      } finally {
        this.uiFlags.isFetchingKanban = false;
      }
    },

    async fetchStageItems(kanbanId, stageId, opts = {}) {
      const { reset = false, cursor = null, limit = STAGE_PAGE_LIMIT } = opts;
      const meta = this.stageMeta[stageId] || {};
      if (meta.isLoading) return;
      this.stageMeta[stageId] = {
        ...meta,
        isLoading: true,
      };
      try {
        const { data } = await KanbanAPI.getFunnelItems(kanbanId, {
          stageId,
          mode: 'cursor',
          limit,
          cursor: reset ? null : cursor,
        });
        const items = Array.isArray(data) ? data : data?.items || [];
        const next = data?.meta?.next_cursor || data?.meta?.nextCursor || null;
        const hasMore = Boolean(next);

        items.forEach(i => this.upsertItem(i));

        const existing = reset ? [] : this.itemIdsByStage[stageId] || [];
        const newIds = items.map(i => Number(i.id));
        const merged = [...new Set([...existing, ...newIds])];
        this.setItemsOrder(stageId, merged);

        this.stageMeta[stageId] = {
          hasMore,
          nextCursor: next,
          isLoading: false,
          loaded: true,
        };
      } catch (e) {
        this.stageMeta[stageId] = {
          ...this.stageMeta[stageId],
          isLoading: false,
          error: true,
        };
        throw e;
      }
    },

    // ---------- mutations remotas ----------
    async createItem({ kanbanId, stageId, payload }) {
      this.uiFlags.isCreatingItem = true;
      try {
        const { data } = await KanbanAPI.createItem(kanbanId, {
          ...payload,
          funnel_stage_id: stageId,
          kanban_stage_id: stageId,
        });
        const item = normalizeEntity(data);
        this.upsertItem(item);
        this.appendItemToStage(stageId, item.id);
        return item;
      } finally {
        this.uiFlags.isCreatingItem = false;
      }
    },

    async moveItem({
      itemId,
      toStageId,
      toPosition = null,
      bypassWip = false,
    }) {
      const item = this.items[itemId];
      if (!item) return undefined;
      const fromStageId = item.kanbanStageId || item.funnelStageId;
      if (fromStageId === toStageId && toPosition == null) return undefined;

      // P3-08: WIP limit check
      const destStage = this.stages[toStageId];
      const destLimit = Number(
        destStage?.wipLimit || destStage?.wip_limit || 0
      );
      if (!bypassWip && destLimit > 0) {
        const currentCount = (this.itemIdsByStage[toStageId] || []).length;
        if (currentCount >= destLimit) {
          this.pendingWipOverride = {
            itemId,
            fromStageId,
            toStageId,
            toPosition,
            limit: destLimit,
            count: currentCount,
          };
          return { wipBlocked: true };
        }
      }

      // snapshot pra rollback
      const snapshot = {
        fromOrder: [...(this.itemIdsByStage[fromStageId] || [])],
        toOrder: [...(this.itemIdsByStage[toStageId] || [])],
        itemPrevStage: fromStageId,
      };

      // optimistic
      this.removeItemFromStage(fromStageId, itemId);
      this.appendItemToStage(toStageId, itemId, toPosition);
      this.items[itemId] = {
        ...item,
        kanbanStageId: toStageId,
        funnelStageId: toStageId,
      };

      this.uiFlags.isMovingItem = true;
      try {
        const kanbanId = item.kanbanId || item.funnelId || this.activeKanbanId;
        const { data } = await KanbanAPI.updateItem(kanbanId, itemId, {
          funnel_stage_id: toStageId,
          kanban_stage_id: toStageId,
          position: toPosition,
        });
        if (data) this.upsertItem(data);

        // P3-03: detecta template configurado na stage destino
        const destStageFinal = this.stages[toStageId];
        const tplId =
          destStageFinal?.defaultMessageTemplateId ||
          destStageFinal?.default_message_template_id;
        if (tplId) {
          this.pendingTemplateConfirm = {
            itemId,
            stageId: toStageId,
            templateId: tplId,
          };
        }

        return this.items[itemId];
      } catch (e) {
        // rollback
        this.setItemsOrder(fromStageId, snapshot.fromOrder);
        this.setItemsOrder(toStageId, snapshot.toOrder);
        this.items[itemId] = {
          ...this.items[itemId],
          kanbanStageId: snapshot.itemPrevStage,
          funnelStageId: snapshot.itemPrevStage,
        };
        throw e;
      } finally {
        this.uiFlags.isMovingItem = false;
      }
    },

    async updateItem({ itemId, patch }) {
      const item = this.items[itemId];
      if (!item) return undefined;
      const kanbanId = item.kanbanId || item.funnelId || this.activeKanbanId;
      const { data } = await KanbanAPI.updateItem(kanbanId, itemId, patch);
      if (data) this.upsertItem(data);
      return this.items[itemId];
    },

    async deleteItem(itemId) {
      const item = this.items[itemId];
      if (!item) return;
      const stageId = item.kanbanStageId || item.funnelStageId;
      const kanbanId = item.kanbanId || item.funnelId || this.activeKanbanId;
      // optimistic
      this.removeItemFromStage(stageId, itemId);
      const backup = { ...item };
      delete this.items[itemId];
      try {
        await KanbanAPI.deleteItem(kanbanId, itemId);
      } catch (e) {
        // rollback
        this.items[itemId] = backup;
        this.appendItemToStage(stageId, itemId);
        throw e;
      }
    },

    // ---------- selecao ----------
    setActiveKanban(id) {
      this.activeKanbanId = id == null ? null : Number(id);
    },

    setActiveCard(id) {
      this.activeCardId = id == null ? null : Number(id);
    },

    toggleSelectItem(id) {
      const numId = Number(id);
      const idx = this.selectedItemIds.indexOf(numId);
      if (idx === -1) this.selectedItemIds.push(numId);
      else this.selectedItemIds.splice(idx, 1);
    },

    clearSelection() {
      this.selectedItemIds = [];
    },

    // P3-03 / P3-08
    clearPendingTemplateConfirm() {
      this.pendingTemplateConfirm = null;
    },

    clearPendingWipOverride() {
      this.pendingWipOverride = null;
    },

    // ---------- real-time (P1-13) ----------
    applyRemoteEvent(evt) {
      if (!evt || !evt.event) return;
      const data = evt.data || {};
      switch (evt.event) {
        case 'kanban_item.created':
        case 'kanban_item.updated':
          if (data.item) {
            this.upsertItem(data.item);
            const stage =
              data.item.kanban_stage_id ||
              data.item.kanbanStageId ||
              data.item.funnel_stage_id;
            if (stage) this.appendItemToStage(stage, Number(data.item.id));
          }
          break;
        case 'kanban_item.moved':
          if (data.item) {
            const id = Number(data.item.id);
            const newStage =
              data.item.kanban_stage_id ||
              data.item.kanbanStageId ||
              data.item.funnel_stage_id;
            const fromStage = data.from_stage_id || data.fromStageId;
            if (fromStage) this.removeItemFromStage(fromStage, id);
            this.upsertItem(data.item);
            if (newStage) this.appendItemToStage(newStage, id);
          }
          break;
        case 'kanban_item.deleted':
          if (data.id) {
            const id = Number(data.id);
            const item = this.items[id];
            if (item) {
              const stage = item.kanbanStageId || item.funnelStageId;
              if (stage) this.removeItemFromStage(stage, id);
              delete this.items[id];
            }
          }
          break;
        case 'kanban_stage.created':
        case 'kanban_stage.updated':
          if (data.stage) {
            this.upsertStage(data.stage);
            const kid = data.stage.kanban_id || data.stage.kanbanId;
            const order = this.stageIds[kid] || [];
            if (!order.includes(Number(data.stage.id))) {
              this.setStageOrder(kid, [...order, Number(data.stage.id)]);
            }
          }
          break;
        case 'kanban_stage.reordered':
          if (data.kanban_id && Array.isArray(data.stage_ids)) {
            this.setStageOrder(data.kanban_id, data.stage_ids);
          }
          break;
        case 'kanban_stage.deleted':
          if (data.id) {
            const sid = Number(data.id);
            const stage = this.stages[sid];
            if (stage) {
              const kid = stage.kanbanId;
              const order = this.stageIds[kid] || [];
              this.setStageOrder(
                kid,
                order.filter(id => id !== sid)
              );
              delete this.stages[sid];
              delete this.itemIdsByStage[sid];
            }
          }
          break;
        case 'kanban.updated':
          if (data.kanban) this.upsertKanban(data.kanban);
          break;
        default:
          // evento desconhecido — log silencioso
          break;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useKanbanBoardStore, import.meta.hot));
}
