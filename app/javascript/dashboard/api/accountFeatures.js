/* global axios */
import ApiClient from './ApiClient';

class AccountFeatures extends ApiClient {
  constructor() {
    super('features', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  // MERGE, e nao replace: manda so o que mudou. O backend chama `enable_features`/`disable_features`
  // (incrementais) em vez de `selected_feature_flags=`, que zeraria todas as outras.
  update(features) {
    return axios.patch(this.url, { features });
  }
}

export default new AccountFeatures();
