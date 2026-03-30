/* global axios */
import ApiClient from '../ApiClient';

class EnterpriseAccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true, enterprise: true });
  }

  checkout() {
    return axios.post(`${this.baseUrl()}/checkout`);
  }

  subscription() {
    return axios.post(`${this.baseUrl()}/subscription`);
  }

  getLimits() {
    return axios.get(`${this.baseUrl()}/limits`);
  }

  toggleDeletion(action) {
    return axios.post(`${this.baseUrl()}/toggle_deletion`, {
      action_type: action,
    });
  }

  createTopupCheckout(credits) {
    return axios.post(`${this.baseUrl()}/topup_checkout`, { credits });
  }
}

export default new EnterpriseAccountAPI();
