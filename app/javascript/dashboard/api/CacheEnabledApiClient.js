/* global axios */
import { DataManager } from '../helper/CacheHelper/DataManager';
import ApiClient from './ApiClient';

const CACHE_KEYS_TTL_MS = 5000;
const cacheKeysCache = {};
const cacheKeysFetchPromises = {};

async function getCacheKeysWithDedup(accountId) {
  const cached = cacheKeysCache[accountId];
  if (
    cached &&
    cached.keys &&
    Date.now() - cached.timestamp < CACHE_KEYS_TTL_MS
  ) {
    return cached.keys;
  }
  if (cacheKeysFetchPromises[accountId]) {
    return cacheKeysFetchPromises[accountId];
  }
  const fetchPromise = axios
    .get(`/api/v1/accounts/${accountId}/cache_keys`)
    .then(response => {
      const keys = response.data.cache_keys;
      cacheKeysCache[accountId] = { keys, timestamp: Date.now() };
      delete cacheKeysFetchPromises[accountId];
      return keys;
    })
    .catch(err => {
      delete cacheKeysFetchPromises[accountId];
      throw err;
    });
  cacheKeysFetchPromises[accountId] = fetchPromise;
  return fetchPromise;
}

class CacheEnabledApiClient extends ApiClient {
  constructor(resource, options = {}) {
    super(resource, options);
    this.dataManager = new DataManager(this.accountIdFromRoute);
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    throw new Error('cacheModelName is not defined');
  }

  get(cache = false) {
    if (cache) {
      return this.getFromCache();
    }

    return this.getFromNetwork();
  }

  getFromNetwork() {
    return axios.get(this.url);
  }

  // eslint-disable-next-line class-methods-use-this
  extractDataFromResponse(response) {
    return response.data.payload;
  }

  // eslint-disable-next-line class-methods-use-this
  marshallData(dataToParse) {
    return { data: { payload: dataToParse } };
  }

  async getFromCache() {
    try {
      // IDB is not supported in Firefox private mode: https://bugzilla.mozilla.org/show_bug.cgi?id=781982
      await this.dataManager.initDb();
    } catch {
      return this.getFromNetwork();
    }

    const cacheKeys = await getCacheKeysWithDedup(this.accountIdFromRoute);
    const cacheKeyFromApi = cacheKeys[this.cacheModelName];
    const isCacheValid = await this.validateCacheKey(cacheKeyFromApi);

    let localData = [];
    if (isCacheValid) {
      localData = await this.dataManager.get({
        modelName: this.cacheModelName,
      });
    }

    if (localData.length === 0) {
      return this.refetchAndCommit(cacheKeyFromApi);
    }

    return this.marshallData(localData);
  }

  async refetchAndCommit(newKey = null) {
    const response = await this.getFromNetwork();

    try {
      await this.dataManager.initDb();

      this.dataManager.replace({
        modelName: this.cacheModelName,
        data: this.extractDataFromResponse(response),
      });

      await this.dataManager.setCacheKeys({
        [this.cacheModelName]: newKey,
      });
    } catch {
      // Ignore error
    }

    return response;
  }

  async validateCacheKey(cacheKeyFromApi) {
    if (!this.dataManager.db) {
      await this.dataManager.initDb();
    }

    const cachekey = await this.dataManager.getCacheKey(this.cacheModelName);
    return cacheKeyFromApi === cachekey;
  }
}

export default CacheEnabledApiClient;
