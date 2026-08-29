/* global axios */
import ApiClient from './ApiClient';

/**
 * Bloco 4.18 — as quatro decisões do lead incompleto.
 *
 * Endpoint próprio, e não `accounts/update`, porque os dois lados precisam do valor
 * RESOLVIDO: o `show` devolve o que o servidor vai fazer (com o padrão declarado no lugar da
 * chave ausente) e o `update` devolve o valor já normalizado. É o que impede a tela de exibir
 * "para sempre" num campo de retenção que o servidor lê como 30 dias.
 *
 * `get()` vem do `ApiClient` e já bate em `/api/v1/accounts/:id/partial_lead_settings`. Só o
 * `set` precisa existir aqui: a rota é `resource` singular, então o `update(id, data)` do pai,
 * que monta `.../partial_lead_settings/:id`, cairia num 404.
 */
class PartialLeadSettingsAPI extends ApiClient {
  constructor() {
    super('partial_lead_settings', { accountScoped: true });
  }

  set(settings) {
    return axios.patch(this.url, settings);
  }
}

export default new PartialLeadSettingsAPI();
