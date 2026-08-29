import partialLeadSettingsAPI from '../partialLeadSettings';
import reportsAPI from '../reports';
import ApiClient from '../ApiClient';

/**
 * Bloco 4.18 — a URL, que é onde este tipo de tela morre calada.
 *
 * A rota é `resource` singular (`resource :partial_lead_settings`), sem `:id`. O `update`
 * herdado do `ApiClient` monta `.../partial_lead_settings/:id` e cairia num 404 uniforme —
 * exatamente a armadilha já paga nesta base (endpoint morto, 404 igual ao de "não existe",
 * nenhuma pista de que a culpa é da rota). Por isso existe o `set`, e por isso ele é medido.
 */
describe('#PartialLeadSettings API (4.18)', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
    // O `ApiClient` tira o id da conta do caminho da janela, como em produção.
    window.history.pushState({}, '', '/app/accounts/7/settings/general');
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('é um ApiClient escopado na conta', () => {
    expect(partialLeadSettingsAPI).toBeInstanceOf(ApiClient);
  });

  it('lê em /api/v1/accounts/:id/partial_lead_settings', () => {
    partialLeadSettingsAPI.get();

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/7/partial_lead_settings'
    );
  });

  it('grava com PATCH na MESMA URL, sem `:id` pendurado', () => {
    partialLeadSettingsAPI.set({ partial_lead_retention_days: 7 });

    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/7/partial_lead_settings',
      { partial_lead_retention_days: 7 }
    );
  });

  it('o relatório do bloco bate no endpoint v2 do `partial_lead_report`', () => {
    // Mesma razão: o método é novo e a URL é a única coisa que liga a tela ao servidor.
    reportsAPI.getPartialLeads({ from: 1000, to: 2000 });

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v2/accounts/7/partial_lead_report',
      { params: { since: 1000, until: 2000 } }
    );
  });
});
