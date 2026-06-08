/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import PortalAPI from 'dashboard/api/helpCenter/portals';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Espelho Pinia de store/modules/helpCenterPortals/* (Onda 2 P0-05).
const DEFAULT_PORTAL_FLAGS = {
  isFetching: false,
  isUpdating: false,
  isDeleting: false,
  isFetchingSSLStatus: false,
};

const portalAPIs = new PortalAPI();

export const useHelpCenterPortalsStore = defineStore('helpCenterPortals', {
  state: () => ({
    meta: {
      allArticlesCount: 0,
      mineArticlesCount: 0,
      draftArticlesCount: 0,
      archivedArticlesCount: 0,
    },
    portals: {
      byId: {},
      allIds: [],
      uiFlags: { byId: {} },
      meta: { byId: {} },
    },
    uiFlags: {
      allFetched: false,
      isFetching: false,
      isSwitching: false,
      isCreating: false,
      isFetchingItem: false,
      isFetchingSSLStatus: false,
    },
  }),

  getters: {
    uiFlagsIn: state => portalId =>
      state.portals.uiFlags.byId[portalId] || { ...DEFAULT_PORTAL_FLAGS },
    isFetchingPortals: state => state.uiFlags.isFetching,
    isCreatingPortal: state => state.uiFlags.isCreating,
    isSwitchingPortal: state => state.uiFlags.isSwitching,
    isFetchingSSLStatus: state => state.uiFlags.isFetchingSSLStatus,
    portalBySlug: state => slug => state.portals.byId[slug],
    allPortals() {
      return this.portals.allIds.map(id => this.portalBySlug(id));
    },
    count: state => state.portals.allIds.length || 0,
    getMeta: state => state.meta,
  },

  actions: {
    _clearPortals() {
      this.portals.byId = {};
      this.portals.allIds = [];
      this.portals.uiFlags.byId = {};
    },

    _addPortalEntry(portal) {
      this.portals.byId = {
        ...this.portals.byId,
        [portal.slug]: { ...portal },
      };
    },

    _addManyPortalsEntry(portals) {
      const all = { ...this.portals.byId };
      portals.forEach(p => {
        all[p.slug] = p;
      });
      this.portals.byId = all;
    },

    _addPortalId(slug) {
      this.portals.allIds.push(slug);
    },

    _addManyPortalsIds(slugs) {
      this.portals.allIds.push(...slugs);
    },

    _updatePortalEntry(portal) {
      const slug = portal.slug;
      if (!this.portals.allIds.includes(slug)) return;
      this.portals.byId = {
        ...this.portals.byId,
        [slug]: { ...portal },
      };
    },

    _removePortalEntry(slug) {
      if (!slug) return;
      const { [slug]: _removed, ...rest } = this.portals.byId;
      this.portals.byId = rest;
    },

    _removePortalId(slug) {
      this.portals.allIds = this.portals.allIds.filter(s => s !== slug);
    },

    _setHelpPortalUIFlag({ portalSlug, uiFlags }) {
      const current = this.portals.uiFlags.byId[portalSlug];
      this.portals.uiFlags.byId = {
        ...this.portals.uiFlags.byId,
        [portalSlug]: {
          ...DEFAULT_PORTAL_FLAGS,
          ...current,
          ...uiFlags,
        },
      };
    },

    _setSSLSettings({ portalSlug, sslSettings }) {
      const portal = this.portals.byId[portalSlug];
      this.portals.byId = {
        ...this.portals.byId,
        [portalSlug]: {
          ...portal,
          ssl_settings: { ...portal?.ssl_settings, ...sslSettings },
        },
      };
    },

    async index() {
      try {
        this.uiFlags.isFetching = true;
        const {
          data: { payload },
        } = await portalAPIs.get();
        this._clearPortals();
        const slugs = payload.map(p => p.slug);
        this._addManyPortalsEntry(payload);
        this._addManyPortalsIds(slugs);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async show({ portalSlug, locale }) {
      this.uiFlags.isFetchingItem = true;
      try {
        const response = await portalAPIs.getPortal({ portalSlug, locale });
        const {
          data: { meta },
        } = response;
        const {
          all_articles_count: allArticlesCount = 0,
          mine_articles_count: mineArticlesCount = 0,
          draft_articles_count: draftArticlesCount = 0,
          archived_articles_count: archivedArticlesCount = 0,
        } = meta;
        this.meta = {
          ...this.meta,
          allArticlesCount,
          archivedArticlesCount,
          mineArticlesCount,
          draftArticlesCount,
        };
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async create(params) {
      this.uiFlags.isCreating = true;
      try {
        const { data } = await portalAPIs.create(params);
        const slug = data.slug;
        this._addPortalEntry(data);
        this._addPortalId(slug);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ portalSlug, ...portalObj }) {
      this._setHelpPortalUIFlag({ portalSlug, uiFlags: { isUpdating: true } });
      try {
        const { data } = await portalAPIs.updatePortal({
          portalSlug,
          portalObj,
        });
        this._updatePortalEntry(data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this._setHelpPortalUIFlag({
          portalSlug,
          uiFlags: { isUpdating: false },
        });
      }
    },

    async delete({ portalSlug }) {
      this._setHelpPortalUIFlag({ portalSlug, uiFlags: { isDeleting: true } });
      try {
        await portalAPIs.delete(portalSlug);
        this._removePortalEntry(portalSlug);
        this._removePortalId(portalSlug);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this._setHelpPortalUIFlag({
          portalSlug,
          uiFlags: { isDeleting: false },
        });
      }
    },

    async deleteLogo({ portalSlug }) {
      this._setHelpPortalUIFlag({ portalSlug, uiFlags: { isUpdating: true } });
      try {
        await portalAPIs.deleteLogo(portalSlug);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this._setHelpPortalUIFlag({
          portalSlug,
          uiFlags: { isUpdating: false },
        });
      }
    },

    async updatePortal(portal) {
      this._updatePortalEntry(portal);
    },

    async switchPortal(isSwitching) {
      this.uiFlags.isSwitching = isSwitching;
    },

    async sendCnameInstructions({ portalSlug, email }) {
      try {
        await portalAPIs.sendCnameInstructions(portalSlug, email);
      } catch (error) {
        throwErrorMessage(error);
      }
    },

    async sslStatus({ portalSlug }) {
      try {
        this.uiFlags.isFetchingSSLStatus = true;
        const { data } = await portalAPIs.sslStatus(portalSlug);
        this._setSSLSettings({ portalSlug, sslSettings: data });
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isFetchingSSLStatus = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useHelpCenterPortalsStore, import.meta.hot)
  );
}
