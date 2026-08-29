# frozen_string_literal: true

# Bloco 4.18 — as QUATRO decisoes de negocio do lead incompleto, expostas.
#
# Elas existiam desde o miolo (`Widget::PartialLeads::Settings`), com padrao declarado e
# clamp, e nao tinham porta: so davam para mexer por console. Uma retencao que so o time
# de infraestrutura consegue mudar nao e "configuravel", e o aceite do bloco cobra
# configuravel — e por um motivo de LGPD, nao de conforto: e dado pessoal de quem nao
# concluiu nada.
#
# Controller proprio, e nao mais quatro chaves em `permitted_settings_attributes`, por
# duas razoes que se somam:
#
#   1. o valor lido tem de ser o RESOLVIDO. `AccountsController#show` devolve o hash cru de
#      `settings`; aqui a resposta e `Settings#to_h`, entao a tela nunca precisa conhecer o
#      padrao do servidor — ela desenha 5 minutos e 30 dias porque e isso que vai acontecer.
#   2. a escrita tem de ser NORMALIZADA. `settings.merge!(params)` guardaria `"para sempre"`
#      em `retention_days`, a leitura cairia no default e a tela continuaria mostrando o
#      texto digitado: configuracao que mente sobre o proprio efeito.
#
# ADMINISTRADOR nas duas acoes. Nao e zelo: a chave decide se um dado pessoal de terceiro
# passa a ser guardado, e por quanto tempo.
class Api::V1::Accounts::PartialLeadSettingsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def show
    render json: settings.to_h
  end

  def update
    render json: settings.update(partial_lead_params)
  end

  private

  def settings
    @settings ||= Widget::PartialLeads::Settings.new(Current.account)
  end

  # Lista branca fechada — as mesmas quatro chaves de `Settings::WRITABLE_KEYS`. Chave fora
  # da lista nao e rejeitada com erro, e simplesmente ignorada: o `slice` do servico ja e a
  # ultima palavra, e devolver 422 para um campo desconhecido quebraria a tela a cada campo
  # novo que um bloco futuro acrescente.
  def partial_lead_params
    params.permit(*Widget::PartialLeads::Settings::WRITABLE_KEYS)
  end
end
