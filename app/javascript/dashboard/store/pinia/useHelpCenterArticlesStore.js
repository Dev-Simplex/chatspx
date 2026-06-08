/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import articlesAPI from 'dashboard/api/helpCenter/articles';
import { uploadExternalImage, uploadFile } from 'dashboard/helper/uploadHelper';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Espelho Pinia de store/modules/helpCenterArticles/* (Onda 2 P0-05).
const DEFAULT_ARTICLE_FLAGS = {
  isFetching: false,
  isUpdating: false,
  isDeleting: false,
};

export const useHelpCenterArticlesStore = defineStore('helpCenterArticles', {
  state: () => ({
    meta: { count: 0, currentPage: 1 },
    articles: {
      byId: {},
      allIds: [],
      uiFlags: { byId: {} },
    },
    uiFlags: {
      allFetched: false,
      isFetching: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    },
  }),

  getters: {
    uiFlagsById: state => helpCenterId =>
      state.articles.uiFlags.byId[helpCenterId] || { ...DEFAULT_ARTICLE_FLAGS },
    isFetching: state => state.uiFlags.isFetching,
    articleById: state => articleId => state.articles.byId[articleId],
    allArticles() {
      return this.articles.allIds
        .map(id => this.articleById(id))
        .filter(a => a !== undefined);
    },
    allArticlesSortedByPosition() {
      const list = this.articles.allIds
        .map(id => this.articleById(id))
        .filter(a => a !== undefined);
      return list.sort(
        (a, b) => (a.position ?? Infinity) - (b.position ?? Infinity)
      );
    },
    articleStatus: state => articleId => state.articles.byId[articleId]?.status,
    getMeta: state => state.meta,
  },

  actions: {
    _clearArticles() {
      this.articles.allIds = [];
      this.articles.byId = {};
      this.articles.uiFlags.byId = {};
    },

    _addManyArticles(articles) {
      const all = { ...this.articles.byId };
      articles.forEach(a => {
        all[a.id] = a;
      });
      this.articles.byId = all;
    },

    _addManyArticlesId(ids) {
      this.articles.allIds.push(...ids);
    },

    _addArticle(article) {
      if (!article.id) return;
      this.articles.byId[article.id] = article;
    },

    _addArticleId(id) {
      if (!this.articles.allIds.includes(id)) this.articles.allIds.push(id);
    },

    _updateArticle(updated) {
      const id = updated.id;
      if (this.articles.byId[id]) {
        const originalPosition = this.articles.byId[id].position;
        this.articles.byId[id] = { ...updated, position: originalPosition };
      }
    },

    _removeArticle(id) {
      const { [id]: _removed, ...rest } = this.articles.byId;
      this.articles.byId = rest;
    },

    _removeArticleId(id) {
      this.articles.allIds = this.articles.allIds.filter(i => i !== id);
    },

    _updateArticleFlag({ articleId, uiFlags }) {
      const current = this.articles.uiFlags.byId[articleId] || {};
      this.articles.uiFlags.byId[articleId] = {
        ...DEFAULT_ARTICLE_FLAGS,
        ...current,
        ...uiFlags,
      };
    },

    _setArticlePositions(positionsHash) {
      const { byId, allIds } = this.articles;
      Object.entries(positionsHash).forEach(([id, position]) => {
        if (byId[id]) byId[id] = { ...byId[id], position };
      });
      allIds.sort(
        (a, b) =>
          (byId[a]?.position ?? Infinity) - (byId[b]?.position ?? Infinity)
      );
    },

    async index({
      pageNumber,
      portalSlug,
      locale,
      status,
      authorId,
      categorySlug,
    }) {
      try {
        this.uiFlags.isFetching = true;
        const { data } = await articlesAPI.getArticles({
          pageNumber,
          portalSlug,
          locale,
          status,
          authorId,
          categorySlug,
        });
        const payload = camelcaseKeys(data.payload);
        const meta = camelcaseKeys(data.meta);
        const ids = payload.map(a => a.id);
        this._clearArticles();
        this._addManyArticles(payload);
        this.meta = { ...this.meta, ...meta };
        this._addManyArticlesId(ids);
        return ids;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create({ portalSlug, ...articleObj }) {
      this.uiFlags.isCreating = true;
      try {
        const { data } = await articlesAPI.createArticle({
          portalSlug,
          articleObj,
        });
        const payload = camelcaseKeys(data.payload);
        const articleId = payload.id;
        this._addArticle(payload);
        this._addArticleId(articleId);
        this._updateArticleFlag({ articleId, uiFlags: {} });
        return articleId;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async show({ id, portalSlug }) {
      this.uiFlags.isFetching = true;
      try {
        const { data } = await articlesAPI.getArticle({ id, portalSlug });
        const payload = camelcaseKeys(data.payload);
        this._addArticle(payload);
        this._addArticleId(payload.id);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async updateAsync({ portalSlug, articleId, ...articleObj }) {
      this._updateArticleFlag({ articleId, uiFlags: { isUpdating: true } });
      try {
        await articlesAPI.updateArticle({ portalSlug, articleId, articleObj });
        return articleId;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this._updateArticleFlag({ articleId, uiFlags: { isUpdating: false } });
      }
    },

    async update({ portalSlug, articleId, ...articleObj }) {
      this._updateArticleFlag({ articleId, uiFlags: { isUpdating: true } });
      try {
        const { data } = await articlesAPI.updateArticle({
          portalSlug,
          articleId,
          articleObj,
        });
        const payload = camelcaseKeys(data.payload);
        this._updateArticle(payload);
        return articleId;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this._updateArticleFlag({ articleId, uiFlags: { isUpdating: false } });
      }
    },

    async updateArticleMeta({ portalSlug, locale }) {
      try {
        const { data } = await articlesAPI.getArticles({
          pageNumber: 1,
          portalSlug,
          locale,
        });
        const meta = camelcaseKeys(data.meta);
        const { currentPage: _cp, ...rest } = meta;
        this.meta = { ...this.meta, ...rest };
      } catch (error) {
        throwErrorMessage(error);
      }
    },

    async delete({ portalSlug, articleId }) {
      this._updateArticleFlag({ articleId, uiFlags: { isDeleting: true } });
      try {
        await articlesAPI.deleteArticle({ portalSlug, articleId });
        this._removeArticle(articleId);
        this._removeArticleId(articleId);
        return articleId;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this._updateArticleFlag({ articleId, uiFlags: { isDeleting: false } });
      }
    },

    async attachImage({ file }) {
      const { fileUrl } = await uploadFile(file);
      return fileUrl;
    },

    async uploadExternalImage({ url }) {
      const { fileUrl } = await uploadExternalImage(url);
      return fileUrl;
    },

    async reorder({ portalSlug, categorySlug, reorderedGroup }) {
      const oldPositions = Object.keys(reorderedGroup).reduce((map, id) => {
        map[id] = this.articles.byId[id]?.position;
        return map;
      }, {});
      this._setArticlePositions(reorderedGroup);
      try {
        await articlesAPI.reorderArticles({
          portalSlug,
          reorderedGroup,
          categorySlug,
        });
      } catch (error) {
        this._setArticlePositions(oldPositions);
        throw error;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useHelpCenterArticlesStore, import.meta.hot)
  );
}
