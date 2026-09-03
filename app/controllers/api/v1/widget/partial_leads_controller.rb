# frozen_string_literal: true

# Bloco 4.18 — a porta pela qual o widget grava a resposta PARCIAL do pre-chat, antes de
# existir conversa.
#
# Autenticacao: a MESMA do resto do widget (X-Auth-Token -> `@contact_inbox`). A sessao
# nao vem do corpo, vem do TOKEN — senao um cliente adulterado escreveria na sessao de
# outro visitante.
#
# Responde 200 vazio sempre que a requisicao e valida, inclusive quando a captura esta
# DESLIGADA na conta: o widget nao precisa saber (e nao deve saber) da configuracao do
# cliente, e nao ha nada que ele possa fazer com um "nao gravei".
class Api::V1::Widget::PartialLeadsController < Api::V1::Widget::BaseController
  def create
    Widget::PartialLeads::RecordService.new(
      inbox: inbox,
      session_id: @contact_inbox.source_id,
      answers: partial_lead_params[:answers],
      step: partial_lead_params[:step],
      step_key: partial_lead_params[:step_key]
    ).perform

    head :ok
  end

  private

  # `answers` e um mapa ABERTO (o administrador escreve o nome dos campos), entao ele nao
  # cabe numa lista branca de chaves. O saneamento — teto de campos, corte de chave e de
  # valor — mora no RecordService, que e onde ele pode ser testado sem HTTP.
  def partial_lead_params
    params.permit(:website_token, :step, :step_key, answers: {})
  end
end
