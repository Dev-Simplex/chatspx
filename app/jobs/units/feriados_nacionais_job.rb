# frozen_string_literal: true

# Põe os feriados nacionais no calendário de toda unidade e completa o ano novo das datas
# móveis, que não cabem numa regra anual. Roda uma vez por dia e é NO-OP assim que todas as
# unidades estão em dia — `units.feriados_nacionais_ate` diz até onde cada uma foi.
#
# É também o caminho das unidades que já existiam quando isto subiu: na primeira volta depois
# do deploy elas ganham o calendário preenchido, sem migration de dados.
class Units::FeriadosNacionaisJob < ApplicationJob
  queue_as :low

  def perform
    Unit.where('feriados_nacionais_ate IS NULL OR feriados_nacionais_ate < ?', ate)
        .find_each { |unit| Units::FeriadosNacionais.garantir(unit) }
  end

  private

  # O ano de corte sai do fuso do app; a unidade recalcula no fuso dela. Na virada do ano uma
  # unidade pode entrar na lista e não ter o que fazer — o serviço trata como NO-OP.
  def ate
    Date.current.year + Units::FeriadosNacionais::ANOS - 1
  end
end
