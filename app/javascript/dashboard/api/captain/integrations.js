/* global axios */
// Integrações de provedores por conta (Vista/Loft, Google) — usadas pelos agentes.
// Rota backend (account-scoped, multi-tenant). NÃO é captain-namespaced:
//   GET    /api/v1/accounts/:id/integrations                          -> lista [{ provider, enabled, settings }]
//   GET    /api/v1/accounts/:id/integrations/:provider                -> um provider
//   PATCH  /api/v1/accounts/:id/integrations/:provider                -> upsert { enabled, settings }
//   POST   /api/v1/accounts/:id/integrations/:provider/test_connection -> { ok, status }
// :provider ∈ vista | google. Segredos vêm MASCARADOS em `settings` e NÃO devem
// ser reenviados se não mudarem (vide componente: campos com '*' são omitidos).
//
// Obs.: o arquivo legado `dashboard/api/integrations.js` (resource integrations/apps)
// é a API de integrações nativas do Chatwoot (Slack/Shopify/hooks) — não confundir.
import ApiClient from '../ApiClient';

class CaptainIntegrations extends ApiClient {
  constructor() {
    super('integrations', { accountScoped: true });
  }

  // Lista todos os provedores da conta.
  get() {
    return axios.get(this.url);
  }

  // Um provedor específico (vista|google).
  show(provider) {
    return axios.get(`${this.url}/${provider}`);
  }

  // Upsert do provedor. data = { enabled, settings: { ... } }.
  update(provider, data = {}) {
    return axios.patch(`${this.url}/${provider}`, data);
  }

  // Testa a conexão do provedor com as credenciais salvas. -> { ok, status }.
  testConnection(provider) {
    return axios.post(`${this.url}/${provider}/test_connection`);
  }
}

export default new CaptainIntegrations();
