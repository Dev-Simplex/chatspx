/* global axios */
import ApiClient from './ApiClient';

/**
 * Sync manual dos integrantes de um grupo de WhatsApp (inbox WAHA).
 *
 * Endpoint do backend (`Api::V1::Accounts::Conversations::WahaGroupController`,
 * rota `resource :waha_group, only: [:show, :create]`). Este arquivo é só o
 * cliente: se a rota mudar, muda AQUI e em nenhum outro lugar.
 *
 * `POST` = "Sincronizar agora": chama a WAHA e regrava o snapshot em
 * `conversation.additional_attributes.waha_group` (contrato C3 do briefing).
 *
 * ATENÇÃO: o endpoint responde **sempre 200**, de propósito — falha da WAHA não
 * pode quebrar a tela. Quem decide o que mostrar é o front, lendo `ok`/`status`
 * do corpo (`synced`, `cached`, `never_synced`, `throttled`, `failed`,
 * `skipped`). Nunca trate "HTTP 200" como "deu certo".
 *
 * O `GET` existe mas não é usado: o snapshot já vem no payload da conversa.
 */
class GroupParticipantsAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  sync(conversationId) {
    return axios.post(`${this.url}/${conversationId}/waha_group`);
  }
}

export default new GroupParticipantsAPI();
