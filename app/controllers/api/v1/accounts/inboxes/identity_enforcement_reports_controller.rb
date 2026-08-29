# frozen_string_literal: true

# Bloco 4.15 — a rota do relatorio de enforcement de identidade da inbox.
#
# O servico (`Identity::EnforcementReport`) ja existia e ja respondia certo; o que faltava
# era uma URL. Relatorio sem rota nao decide virada nenhuma: quem decide ligar
# `obrigatorio` numa inbox com trafego nao abre `rails console` para saber quantas sessoes
# o 401 vai derrubar. Os dois relatorios irmaos do mesmo plano — `origin_report` (1.22) e
# `partial_lead_report` (4.18) — ja tinham a sua; este e o mesmo molde, com uma diferenca
# deliberada: eles sao da CONTA e este e da INBOX, porque o estado que ele mede
# (`identity_enforcement`) e uma configuracao de inbox e o servico exige uma.
#
# CLASSE NO PLURAL, rota no singular: `resource :identity_enforcement_report` procura
# `IdentityEnforcementReportsController`. Nomear esta classe no singular nao daria erro de
# carga — daria 404 na URL, e um 404 aqui le-se "a inbox nao existe". Foi assim que o cofre
# do 5.02 ficou inacessivel em navegador com a suite inteira verde.
#
# `report#view?` e a mesma autorizacao dos outros relatorios: administrador. E a
# autorizacao vem ANTES da busca da inbox de proposito — assim um agente comum recebe 401
# em vez de descobrir, pelo 404, quais ids de inbox existem.
class Api::V1::Accounts::Inboxes::IdentityEnforcementReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_inbox

  # Sem envelope `payload`, pelo mesmo motivo do painel de diagnostico (5.14): o corpo do
  # servico e o contrato, e embrulhar nao daria erro — daria uma tela vazia e silenciosa.
  def show
    render json: Identity::EnforcementReport.new(inbox: @inbox).perform
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  # SEMPRE escopado na conta atual: id de inbox de outra conta e 404, nunca o relatorio
  # alheio.
  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end
end
