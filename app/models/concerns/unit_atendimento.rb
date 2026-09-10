# O vocabulário de ATENDIMENTO da unidade: fuso, coordenada, distância, e o horário resolvido de
# uma data já com a exceção aplicada. Vive num concern porque é o que a IA consulta, e é bom que
# dê para ler essa fatia sem atravessar o resto do cadastro.
#
# Isto veio do `Spx::Unidade`, a implementação irmã que existia em paralelo — mesma ideia, tabela
# própria e tela própria. Duas fontes de verdade para "onde fica a loja e a que horas abre" é como
# se responde ao cliente com o dado que ninguém está editando: na Tozi a tela viva era a `units` e
# a IA lia da `unidades`. Agora existe uma só, e é esta.
#
# O que MUDOU na adaptação, e por quê:
#   * turno partido — a tabela antiga usava duas linhas no mesmo dia; a `unit_working_hours` tem
#     índice único por dia e expressa o mesmo com `break_start_*`/`break_end_*`. As duas faixas
#     saem daqui, então quem lê continua vendo "07:30 às 11:30 e 13:30 às 17:30".
#   * exceção — a antiga resolvia precedência à mão (unidade > etiqueta > padrão). A `UnitException`
#     é sempre da unidade e tem recorrência, e quem sabe avaliar isso é o `Units::ScheduleEvaluator`,
#     que já roda em produção decidindo se a caixa fecha. Reusar em vez de reimplementar evita a
#     divergência silenciosa entre "a caixa fechou" e "a IA disse que estava aberto".
module UnitAtendimento
  extend ActiveSupport::Concern

  FUSO_PADRAO = 'America/Cuiaba'.freeze
  MINUTOS_DO_DIA = 24 * 60

  # Segunda a domingo, que é como se lê uma grade no Brasil — e não a ordem numérica do Date#wday.
  ORDEM_LEITURA = [1, 2, 3, 4, 5, 6, 0].freeze

  # Uma janela de funcionamento, em minutos desde a meia-noite LOCAL da unidade. Minutos em vez de
  # Time porque a comparação com "agora" é aritmética de relógio de parede, não de instante.
  Faixa = Data.define(:inicio, :fim) do
    # Fim menor ou igual ao início significa que a janela atravessa a meia-noite.
    def contem?(minuto)
      fim > inicio ? minuto >= inicio && minuto < fim : minuto >= inicio || minuto < fim
    end

    def to_s
      "#{hh_mm(inicio)} às #{hh_mm(fim)}"
    end

    private

    def hh_mm(minutos)
      format('%<h>02d:%<m>02d', h: (minutos / 60) % 24, m: minutos % 60)
    end
  end

  # O estado resolvido numa data, já com a exceção aplicada. `por_excecao` existe para quem lê saber
  # que o horário daquele dia NÃO é o de sempre — é o que permite responder "abre mais cedo por
  # causa do feriado" em vez de só cuspir o horário.
  Estado = Data.define(:data, :faixas, :motivo, :por_excecao) do
    def aberta? = faixas.any?
    def por_excecao? = por_excecao
    def aberta_em?(minuto) = faixas.any? { |faixa| faixa.contem?(minuto) }
  end

  included do
    alias_attribute :nome, :name
    alias_attribute :cidade, :city
    alias_attribute :uf, :state
    alias_attribute :endereco, :address
    alias_attribute :telefone, :phone
    alias_attribute :ativa, :active

    scope :ativas, -> { where(active: true) }
    scope :com_coordenada, -> { where.not(latitude: nil).where.not(longitude: nil) }

    before_validation :normalizar_etiquetas
  end

  RAIO_DA_TERRA_KM = 6371.0

  class_methods do
    # Haversine. Entra aqui, e não numa gem de geo, porque é a única conta geográfica do módulo e
    # não depende de rede: a coordenada da unidade é dado carregado, conferido uma vez.
    def distancia_km(lat1, lng1, lat2, lng2)
      return nil if [lat1, lng1, lat2, lng2].any?(&:blank?)

      a = meia_corda(lat1.to_f, lng1.to_f, lat2.to_f, lng2.to_f)
      RAIO_DA_TERRA_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    def normalizar(valor)
      ActiveSupport::Inflector.transliterate(valor.to_s).downcase.strip.presence
    end

    private

    def meia_corda(lat1, lng1, lat2, lng2)
      rad = Math::PI / 180
      dlat = (lat2 - lat1) * rad
      dlng = (lng2 - lng1) * rad
      (Math.sin(dlat / 2)**2) + (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlng / 2)**2))
    end
  end

  def zona
    ActiveSupport::TimeZone[timezone.to_s.presence || FUSO_PADRAO] || ActiveSupport::TimeZone[FUSO_PADRAO]
  end

  def coordenada?
    latitude.present? && longitude.present?
  end

  # `nil` quando falta coordenada dos dois lados — e nil aqui tem que continuar nil para quem chama,
  # porque "não sei a distância" não pode virar zero nem infinito: os dois ordenariam a lista e a
  # resposta pareceria certa.
  def distancia_de(lat, lng)
    self.class.distancia_km(latitude, longitude, lat, lng)
  end

  def etiquetas_normalizadas
    Array(etiquetas).filter_map { |etiqueta| self.class.normalizar(etiqueta) }
  end

  def etiqueta?(valor)
    alvo = self.class.normalizar(valor)
    alvo.present? && etiquetas_normalizadas.include?(alvo)
  end

  # Ausência de grade NÃO é "fechada": é "não sei". Quem lê precisa distinguir as duas, senão a
  # resposta ao cliente vira invenção com cara de dado. E a distinção é POR DIA: quem cadastra só os
  # dias úteis tem sábado desconhecido, não sábado fechado.
  def horario_cadastrado?
    working_hours.any?
  end

  def dia_cadastrado?(dia_semana)
    working_hours.any? { |hora| hora.day_of_week == dia_semana }
  end

  def faixas_padrao(dia_semana)
    working_hours.select { |hora| hora.day_of_week == dia_semana }.flat_map(&:faixas).sort_by(&:inicio)
  end

  # `escopo_excecoes` recebe uma coleção JÁ CARREGADA para quem lista várias unidades consultar as
  # exceções uma vez só — sem isso é uma consulta por unidade por data.
  def estado_em(data, escopo_excecoes: nil)
    regra = regra_do_dia(data, escopo_excecoes)
    Estado.new(data: data, faixas: faixas_em(data, regra),
               motivo: regra&.name.presence, por_excecao: regra.present?)
  end

  private

  # Quem decide se a regra vale na data é o MESMO avaliador que decide se a caixa fecha — não uma
  # segunda leitura da recorrência, que divergiria calada.
  def regra_do_dia(data, escopo_excecoes)
    candidatas = escopo_excecoes || UnitException.where(unit_id: id).to_a
    candidatas.select { |regra| regra.unit_id == id && Units::ScheduleEvaluator.rule_on?(regra, data) }
              .max_by { |regra| [regra.created_at || Time.zone.at(0), regra.id.to_i] }
  end

  def faixas_em(data, regra)
    return faixas_padrao(data.wday) if regra.nil?
    return [] if regra.closed_all_day?

    inicio = minutos_de(regra.open_hour, regra.open_minutes)
    fim = minutos_de(regra.close_hour, regra.close_minutes)
    # Exceção que não fecha e não traz horário quer dizer "abre no horário de sempre".
    inicio && fim ? [Faixa.new(inicio: inicio, fim: fim)] : faixas_padrao(data.wday)
  end

  def minutos_de(hora, minuto)
    return nil if hora.nil?

    (hora.to_i * 60) + minuto.to_i
  end

  def normalizar_etiquetas
    self.etiquetas = Array(etiquetas).filter_map { |etiqueta| self.class.normalizar(etiqueta) }.uniq
  end
end
