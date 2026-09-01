# Unidade física de um cliente (loja, filial, escritório) — contrato em docs/contratos/unidades.md.
#
# Multi-tenant e opt-in: conta sem unidade cadastrada não muda de comportamento em nada.
# Taxonomia PLANA com etiquetas, sem hierarquia rede → regional → loja, pelo mesmo motivo do
# `distribuicao_produtos`: hierarquia rígida quebra na primeira exceção.
class Spx::Unidade < ApplicationRecord
  self.table_name = 'unidades'

  FUSO_PADRAO = 'America/Cuiaba'.freeze

  # Dias da semana na ordem em que se lê uma grade no Brasil (segunda a domingo), e não na ordem
  # numérica do Date#wday. Vive aqui pra tool e rake condensarem a semana do mesmo jeito.
  ORDEM_LEITURA = [1, 2, 3, 4, 5, 6, 0].freeze

  # Uma janela de funcionamento, em minutos desde a meia-noite LOCAL da unidade. Minutos em vez
  # de Time porque a comparação com "agora" é aritmética de relógio de parede, não de instante.
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

  # O estado resolvido de uma unidade numa data, já com a exceção aplicada. `por_excecao` existe
  # pra quem lê saber que o horário daquele dia NÃO é o de sempre — é o que permite responder
  # "abre por causa da campanha" em vez de só cuspir o horário.
  Estado = Data.define(:data, :faixas, :motivo, :por_excecao) do
    def aberta?
      faixas.any?
    end

    def por_excecao?
      por_excecao
    end

    def aberta_em?(minuto)
      faixas.any? { |faixa| faixa.contem?(minuto) }
    end
  end

  belongs_to :account

  has_many :horarios, -> { order(:dia_semana, :abre) },
           class_name: 'Spx::UnidadeHorario', dependent: :destroy, inverse_of: :unidade
  has_many :excecoes, class_name: 'Spx::UnidadeExcecao', dependent: :destroy, inverse_of: :unidade

  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validates :nome, presence: true

  before_validation :normalizar_etiquetas

  scope :ativas, -> { where(ativa: true) }

  class << self
    # Uma linha (de horário padrão ou de exceção) só vira faixa quando não está marcada como
    # fechada E traz os dois horários. Fica aqui pra as duas tabelas decidirem igual.
    def faixa(fechada:, abre:, fecha:)
      return nil if fechada || abre.blank? || fecha.blank?

      Faixa.new(inicio: minutos_do_dia(abre), fim: minutos_do_dia(fecha))
    end

    def minutos_do_dia(valor)
      (valor.hour * 60) + valor.min
    end

    def normalizar(valor)
      texto = ActiveSupport::Inflector.transliterate(valor.to_s).downcase.strip
      texto.presence
    end
  end

  def zona
    ActiveSupport::TimeZone[timezone.to_s.presence || FUSO_PADRAO] || ActiveSupport::TimeZone[FUSO_PADRAO]
  end

  def etiquetas_normalizadas
    Array(etiquetas).filter_map { |etiqueta| self.class.normalizar(etiqueta) }
  end

  def etiqueta?(valor)
    alvo = self.class.normalizar(valor)
    alvo.present? && etiquetas_normalizadas.include?(alvo)
  end

  # Ausência de grade cadastrada NÃO é "fechada": é "não sei". Quem lê precisa distinguir as
  # duas, senão a resposta ao cliente vira invenção com cara de dado.
  #
  # E a distinção é POR DIA, não pela unidade: quem cadastra só os dias úteis tem sábado
  # desconhecido, não sábado fechado. Só a checagem por unidade deixava passar exatamente esse
  # caso — a unidade "tem grade", então o sábado sem linha saía como fechado.
  def horario_cadastrado?
    horarios.any?
  end

  def dia_cadastrado?(dia_semana)
    horarios.any? { |horario| horario.dia_semana == dia_semana }
  end

  def faixas_padrao(dia_semana)
    horarios.select { |horario| horario.dia_semana == dia_semana }.filter_map(&:faixa).sort_by(&:inicio)
  end

  # A REGRA que decide o que a IA responde (§4 do contrato): exceção de unidade vence exceção de
  # etiqueta, que vence o horário padrão. Mais específico vence; empate na especificidade, vence
  # a criada por último.
  #
  # `escopo_excecoes` recebe uma coleção JÁ CARREGADA pra quem lista várias unidades consultar as
  # exceções da conta uma vez só — sem isso é uma consulta por unidade por data.
  def estado_em(data, escopo_excecoes: nil)
    excecao = excecao_vigente(data, escopo_excecoes)
    Estado.new(data: data, faixas: faixas_em(data, excecao),
               motivo: excecao&.motivo.presence, por_excecao: excecao.present?)
  end

  private

  def excecao_vigente(data, escopo_excecoes)
    candidatas = escopo_excecoes || Spx::UnidadeExcecao.where(account_id: account_id).vigentes_em(data).to_a
    aplicaveis = candidatas.select { |excecao| excecao.vigente_em?(data) && excecao.aplica_a?(self) }
    aplicaveis.max_by { |excecao| [excecao.especificidade, excecao.created_at || Time.zone.at(0), excecao.id.to_i] }
  end

  def faixas_em(data, excecao)
    return faixas_padrao(data.wday) if excecao.nil?
    return [] if excecao.fechada?

    # Exceção que não fecha e não traz horário quer dizer "abre no horário de sempre" — é como
    # uma unidade escapa de um fechamento de etiqueta ou de conta sem repetir a grade inteira.
    faixa = excecao.faixa
    faixa ? [faixa] : faixas_padrao(data.wday)
  end

  def normalizar_etiquetas
    self.etiquetas = Array(etiquetas).filter_map { |etiqueta| self.class.normalizar(etiqueta) }.uniq
  end
end
