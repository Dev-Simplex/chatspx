# frozen_string_literal: true

# Integrantes do grupo de WhatsApp de uma conversa (WAHA).
#
#   GET  /api/v1/accounts/{account_id}/conversations/{display_id}/waha_group
#        Le o snapshot ja gravado. NAO chama a WAHA — resposta instantanea.
#
#   POST /api/v1/accounts/{account_id}/conversations/{display_id}/waha_group
#        "Sincronizar agora": chama a WAHA, regrava o snapshot e devolve o
#        resultado. Tem piso de 30s por conversa (o botao nao vira marreta).
#
# Shape da resposta (identico nos dois verbos, sempre HTTP 200):
#   { "ok": true|false,
#     "status": "synced"|"cached"|"never_synced"|"throttled"|"failed"|"skipped",
#     "reason": null|"not_a_group"|"no_session"|"waha_unavailable"|"waha_error"|
#               "force_throttled"|"empty_participants"|"unexpected_error",
#     "waha_group": null | { "participants":[{lid,phone,name,admin}], "count":N,
#                            "synced_at":"iso8601" } }
#
# Por que sempre 200: falha da WAHA nao pode quebrar a tela. O front decide o que
# mostrar a partir de `ok`/`status`; `waha_group: null` significa "nunca
# sincronizado". Autorizacao e escopo de conta vem do BaseController.
class Api::V1::Accounts::Conversations::WahaGroupController < Api::V1::Accounts::Conversations::BaseController
  def show
    snapshot = @conversation.additional_attributes&.dig('waha_group')
    render json: payload(success: true, status: snapshot.present? ? 'cached' : 'never_synced', reason: nil, snapshot: snapshot)
  end

  def create
    result = Waha::GroupSyncService.new(@conversation, force: true).perform
    render json: payload(success: result.ok?, status: result.status, reason: result.reason, snapshot: result.snapshot)
  end

  private

  def payload(success:, status:, reason:, snapshot:)
    { ok: success, status: status, reason: reason, waha_group: snapshot }
  end
end
