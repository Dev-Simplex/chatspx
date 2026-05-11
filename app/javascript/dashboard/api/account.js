/* global axios */
import ApiClient from './ApiClient';

class AccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  createAccount(data) {
    return axios.post(`${this.apiVersion}/accounts`, data);
  }

  async getCacheKeys() {
    const response = await axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/cache_keys`
    );
    return response.data.cache_keys;
  }

  uploadChatWallpaper(file) {
    const formData = new FormData();
    formData.append('image', file);
    return axios.post(
      `/api/v1/accounts/${this.accountIdFromRoute}/chat_wallpaper`,
      formData,
      { headers: { 'Content-Type': 'multipart/form-data' } }
    );
  }

  removeChatWallpaper() {
    return axios.delete(
      `/api/v1/accounts/${this.accountIdFromRoute}/chat_wallpaper`
    );
  }
}

export default new AccountAPI();
