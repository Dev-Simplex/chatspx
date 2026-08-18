# Bloco 1.22 — de onde vieram os atendimentos.
#
# Controller próprio, e não mais uma action no `ReportsController`: aquele já está em 175 linhas,
# que é o teto do `Metrics/ClassLength` deste repo. Afrouxar o gate para caber mais um relatório
# seria pagar a dívida de outra pessoa com o orçamento do próximo.
class Api::V2::Accounts::OriginReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  # O serviço devolve o período anterior à entrada da medição contado à parte, para a tela não
  # mostrar vazio onde houve conversa sem coleta — vazio é lido como "não veio ninguém".
  def show
    render json: Tracking::OriginReport.new(
      account: Current.account,
      since: epoch_param(params[:since], 30.days.ago),
      until_time: epoch_param(params[:until], Time.current)
    ).perform
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  # `since`/`until` chegam em epoch, como no resto dos relatórios.
  def epoch_param(value, padrao)
    return padrao if value.blank?

    Time.zone.at(value.to_i)
  end
end
