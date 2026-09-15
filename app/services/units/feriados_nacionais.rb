# frozen_string_literal: true

# Feriado nacional no calendário da unidade — sem ninguém digitar e sem apertar nada.
#
# Nove são de DATA FIXA (25/12 é sempre 25/12) e viram UMA regra anual cada: valem deste
# ano em diante, para sempre, sem recadastro. Três andam com a Páscoa — Carnaval,
# Sexta-feira Santa e Corpus Christi — e data móvel não cabe em "todo ano no dia tal":
# cada ano vira uma linha própria, calculada aqui. Daí `ANOS`, e daí o job diário, que
# completa o ano novo quando ele entra no horizonte.
#
# `units.feriados_nacionais_ate` é a memória disso: diz até que ano a unidade já foi
# preenchida. É ela que faz o automático NÃO brigar com quem apaga — a filial que abre no
# Carnaval apaga a linha e ela não volta, porque o ano dela já está marcado como gerado.
#
# São REGRAS COMUNS, não uma categoria nova: aparecem na lista, se editam e se apagam como
# qualquer feriado digitado à mão, e os dois avaliadores (Ruby e JS) já sabem lê-las.
#
# Carnaval e Corpus Christi são ponto facultativo, não feriado por lei — entram porque o
# comércio fecha, e somem num clique para quem abre.
class Units::FeriadosNacionais
  # Anos de datas móveis mantidos à frente. Cinco cobre a vida útil de um cadastro sem
  # encher a lista: são três linhas por ano.
  ANOS = 5

  # [mês, dia, nome] — as datas fixas, na ordem do ano.
  FIXOS = [
    [1, 1, 'Confraternização Universal'],
    [4, 21, 'Tiradentes'],
    [5, 1, 'Dia do Trabalho'],
    [9, 7, 'Independência do Brasil'],
    [10, 12, 'Nossa Senhora Aparecida'],
    [11, 2, 'Finados'],
    [11, 15, 'Proclamação da República'],
    [11, 20, 'Consciência Negra'],
    [12, 25, 'Natal']
  ].freeze

  # [dias a partir do Domingo de Páscoa, nome] — é o que faz a data móvel ser móvel.
  MOVEIS = [
    [-47, 'Carnaval'],
    [-2, 'Sexta-feira Santa'],
    [60, 'Corpus Christi']
  ].freeze

  def self.garantir(unit)
    new(unit).garantir
  end

  # Domingo de Páscoa pelo algoritmo de Meeus/Butcher (calendário gregoriano). É dele que
  # saem as três datas móveis, e é a única conta desta feature que não dá para ler no banco.
  # rubocop:disable Metrics/AbcSize -- fórmula fechada: quebrar em métodos só esconderia o algoritmo
  def self.domingo_de_pascoa(ano)
    a = ano % 19
    b, c = ano.divmod(100)
    d, e = b.divmod(4)
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = ((19 * a) + b - d - g + 15) % 30
    i, k = c.divmod(4)
    l = (32 + (2 * e) + (2 * i) - h - k) % 7
    m = (a + (11 * h) + (22 * l)) / 451
    dias = h + l - (7 * m) + 114
    Date.new(ano, dias / 31, (dias % 31) + 1)
  end
  # rubocop:enable Metrics/AbcSize

  def initialize(unit)
    @unit = unit
    # No fuso da unidade: em Cuiabá o dia vira uma hora depois, e o feriado de hoje não
    # pode ser descartado como "já passou" porque em UTC já é amanhã.
    @hoje = Time.current.in_time_zone(unit.timezone).to_date
    @regras = unit.exceptions.to_a
  end

  def garantir
    return if em_dia?

    criar_fixos if @unit.feriados_nacionais_ate.nil?
    criar_moveis
    # update_column de propósito: a marca de bookkeeping não pode reprovar numa validação
    # do cadastro nem disparar callback.
    @unit.update_column(:feriados_nacionais_ate, ate) # rubocop:disable Rails/SkipsModelValidations
    # A tela recebe a unidade no mesmo request que a criou: sem o reset, a resposta sairia
    # com a lista de regras de antes.
    @unit.association(:exceptions).reset
  end

  private

  def ate
    @hoje.year + ANOS - 1
  end

  def em_dia?
    @unit.feriados_nacionais_ate.present? && @unit.feriados_nacionais_ate >= ate
  end

  # Só os anos que faltam: quem já foi gerado até 2030 ganha 2031 e mais nada.
  def primeiro_ano
    @unit.feriados_nacionais_ate ? @unit.feriados_nacionais_ate + 1 : @hoje.year
  end

  # A data fixa começa no ano corrente mesmo que já tenha passado: a regra anual só vale de
  # `starts_on` em diante, então o 1º de janeiro passado não polui o calendário e o que
  # ainda vem neste ano (12/10, 25/12) já aparece marcado.
  def criar_fixos
    FIXOS.each do |mes, dia, nome|
      data = Date.new(@hoje.year, mes, dia)
      criar(nome, data, :anual, data >= @hoje ? data : data.next_year)
    end
  end

  # Data móvel que já passou não entra — seria linha morta na lista.
  def criar_moveis
    (primeiro_ano..ate).each do |ano|
      pascoa = self.class.domingo_de_pascoa(ano)
      MOVEIS.each do |deslocamento, nome|
        data = pascoa + deslocamento
        criar(nome, data, :nao_repete, data) if data >= @hoje
      end
    end
  end

  # `proxima` é o dia em que a regra cai pela primeira vez — é por ele que se sabe se o dia
  # já está ocupado, e é o que distingue a regra anual de 25/12 de uma de 26/12.
  def criar(nome, starts_on, frequency, proxima)
    return if dia_ocupado?(proxima)

    @regras << @unit.exceptions.create!(
      name: nome, category: :feriado, closed_all_day: true,
      starts_on: starts_on, frequency: frequency
    )
  end

  # Dia que já é feriado não ganha um segundo feriado em cima — nem o que o admin marcou à
  # mão, nem a Sexta-feira Santa que cai sobre o Tiradentes (21/04: aconteceu em 2000, volta
  # em 2079). Só olha regra da categoria feriado: um "plantão de sexta" (evento) não pode
  # engolir a Sexta-feira Santa.
  def dia_ocupado?(data)
    @regras.any? { |regra| regra.feriado? && Units::ScheduleEvaluator.rule_on?(regra, data) }
  end
end
