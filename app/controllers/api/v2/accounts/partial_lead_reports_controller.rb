# frozen_string_literal: true

# Bloco 4.18 — "quantos leads perdemos e onde".
#
# Controller proprio pelo mesmo motivo do `OriginReportsController` (bloco 1.22): o
# `ReportsController` ja esta no teto de `Metrics/ClassLength`, e afrouxar o gate para
# caber mais um relatorio e pagar divida de outra pessoa com o orcamento do proximo.
#
# `report#view?` e a mesma autorizacao dos demais relatorios: quem ve numero de conversa
# ve numero de lead perdido. O endpoint NUNCA devolve as respostas do visitante — so
# CONTAGENS. O dado pessoal de quem nao concluiu nao precisa sair da base para o
# relatorio existir.
class Api::V2::Accounts::PartialLeadReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: Widget::PartialLeads::Report.new(
      account: Current.account,
      inbox: inbox,
      since: epoch_param(params[:since], 30.days.ago),
      until_time: epoch_param(params[:until], Time.current)
    ).perform
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  # A inbox e opcional e SEMPRE escopada na conta atual — id de inbox de outra conta
  # devolve o relatorio da conta inteira, nunca o dado alheio.
  def inbox
    return if params[:inbox_id].blank?

    Current.account.inboxes.find_by(id: params[:inbox_id])
  end

  def epoch_param(value, padrao)
    return padrao if value.blank?

    Time.zone.at(value.to_i)
  end
end
