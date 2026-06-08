/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import categoriesAPI from 'dashboard/api/helpCenter/categories.js';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Espelho Pinia de store/modules/helpCenterCategories/* (Onda 2 P0-05).
const DEFAULT_CATEGORY_FLAGS = {
  isFetching: false,
  isUpdating: false,
  isDeleting: false,
};

export const useHelpCenterCategoriesStore = defineStore(
  'helpCenterCategories',
  {
    state: () => ({
      categories: {
        byId: {},
        byLocale: {},
        allIds: [],
        uiFlags: { byId: {} },
      },
      meta: {},
      uiFlags: {
        allFetched: false,
        isFetching: false,
        isCreating: false,
      },
    }),

    getters: {
      uiFlagsById: state => helpCenterId =>
        state.categories.uiFlags.byId[helpCenterId] || {
          ...DEFAULT_CATEGORY_FLAGS,
        },
      isFetching: state => state.uiFlags.isFetching,
      isCreating: state => state.uiFlags.isCreating,
      categoryById: state => id => state.categories.byId[id],
      allCategories() {
        return this.categories.allIds.map(id => this.categoryById(id));
      },
      allCategoriesSortedByPosition() {
        return this.categories.allIds
          .map(id => this.categoryById(id))
          .filter(c => c !== undefined)
          .sort((a, b) => (a.position ?? Infinity) - (b.position ?? Infinity));
      },
      categoriesByLocaleCode() {
        return localeCode => {
          const list = this.categories.allIds.map(id => this.categoryById(id));
          return list.filter(c => c && c.locale === localeCode);
        };
      },
      getMeta: state => state.meta,
    },

    actions: {
      _clearCategories() {
        this.categories.byId = {};
        this.categories.allIds = [];
        this.categories.uiFlags.byId = {};
      },

      _addManyCategories(categories) {
        const all = { ...this.categories.byId };
        categories.forEach(c => {
          all[c.id] = c;
        });
        this.categories.byId = all;
      },

      _addManyCategoriesId(ids) {
        this.categories.allIds.push(...ids);
      },

      _addCategory(category) {
        if (!category.id) return;
        this.categories.byId[category.id] = { ...category };
      },

      _addCategoryId(id) {
        this.categories.allIds.push(id);
      },

      _updateCategory(category) {
        const id = category.id;
        if (!this.categories.allIds.includes(id)) return;
        this.categories.byId[id] = { ...category };
      },

      _removeCategory(id) {
        const { [id]: _removed, ...rest } = this.categories.byId;
        this.categories.byId = rest;
      },

      _removeCategoryId(id) {
        this.categories.allIds = this.categories.allIds.filter(i => i !== id);
      },

      _addCategoryFlag({ categoryId, uiFlags }) {
        const current = this.categories.uiFlags.byId[categoryId];
        this.categories.uiFlags.byId[categoryId] = {
          ...DEFAULT_CATEGORY_FLAGS,
          ...current,
          ...uiFlags,
        };
      },

      _setCategoryPositions(positionsHash) {
        const { byId, allIds } = this.categories;
        Object.entries(positionsHash).forEach(([id, position]) => {
          if (byId[id]) byId[id] = { ...byId[id], position };
        });
        allIds.sort(
          (a, b) =>
            (byId[a]?.position ?? Infinity) - (byId[b]?.position ?? Infinity)
        );
      },

      async index({ portalSlug, locale }) {
        try {
          this.uiFlags.isFetching = true;
          if (portalSlug) {
            const {
              data: { payload },
            } = await categoriesAPI.get({ portalSlug, locale });
            this._clearCategories();
            const ids = payload.map(c => c.id);
            this._addManyCategories(payload);
            this._addManyCategoriesId(ids);
            return ids;
          }
          return '';
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this.uiFlags.isFetching = false;
        }
      },

      async create({ portalSlug, categoryObj }) {
        this.uiFlags.isCreating = true;
        try {
          const {
            data: { payload },
          } = await categoriesAPI.create({
            portalSlug,
            categoryObj,
          });
          const id = payload.id;
          this._addCategory(payload);
          this._addCategoryId(id);
          return id;
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this.uiFlags.isCreating = false;
        }
      },

      async update({ portalSlug, categoryId, categoryObj }) {
        this._addCategoryFlag({ categoryId, uiFlags: { isUpdating: true } });
        try {
          const {
            data: { payload },
          } = await categoriesAPI.update({
            portalSlug,
            categoryId,
            categoryObj,
          });
          this._updateCategory(payload);
          return categoryId;
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this._addCategoryFlag({ categoryId, uiFlags: { isUpdating: false } });
        }
      },

      async delete({ portalSlug, categoryId }) {
        this._addCategoryFlag({ categoryId, uiFlags: { isDeleting: true } });
        try {
          await categoriesAPI.delete({ portalSlug, categoryId });
          this._removeCategory(categoryId);
          this._removeCategoryId(categoryId);
          return categoryId;
        } catch (error) {
          return throwErrorMessage(error);
        } finally {
          this._addCategoryFlag({ categoryId, uiFlags: { isDeleting: false } });
        }
      },

      async reorder({ portalSlug, reorderedGroup }) {
        const oldPositions = Object.keys(reorderedGroup).reduce((map, id) => {
          map[id] = this.categories.byId[id]?.position;
          return map;
        }, {});
        this._setCategoryPositions(reorderedGroup);
        try {
          await categoriesAPI.reorder({ portalSlug, reorderedGroup });
        } catch (error) {
          this._setCategoryPositions(oldPositions);
          throw error;
        }
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useHelpCenterCategoriesStore, import.meta.hot)
  );
}
