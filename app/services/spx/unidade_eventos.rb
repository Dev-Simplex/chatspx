# O que está acontecendo na unidade agora, ou está marcado para os próximos dias — e que a pessoa
# pode perguntar sem citar data nenhuma.
#
# Existe porque a agenda respondia só o que foi perguntado: quem escreve "tem alguma coisa
# acontecendo aí?" não cita dia, e antes disso nenhuma exceção era sequer carregada. O evento
# ficava invisível para o agente justamente na pergunta que é sobre ele.
#
# FERIADO fica de fora de propósito: ele só muda o horário, e a linha de horário já responde por
# ele. O que entra aqui é o que muda a EXPERIÊNCIA de quem vai até lá e tem nome que a pessoa
# reconhece — evento, obra, temporada.
class Spx::UnidadeEventos
  # Quantos dias à frente se enxerga. Curto de propósito: o que vale é o que a pessoa ainda pega
  # indo até lá. Janela longa transforma agenda anual em ruído em toda consulta.
  JANELA_DIAS = 14
  LIMITE = 3
  DIAS_ABREVIADOS = %w[dom seg ter qua qui sex sáb].freeze

  def initialize(unidade, excecoes)
    @unidade = unidade
    @excecoes = excecoes || []
  end

  # Uma linha por evento, prontas para o retorno da ferramenta. Vazio quando não há nada à vista —
  # e vazio aqui é ausência de evento, não falha de consulta.
  def linhas
    hoje = Time.now.in_time_zone(@unidade.zona).to_date
    janela = (hoje..(hoje + JANELA_DIAS))

    candidatas.filter_map do |regra|
      datas = janela.select { |data| ::Units::ScheduleEvaluator.rule_on?(regra, data) }
      next if datas.empty?

      "#{rotulo(regra)}: #{regra.name} — #{periodo(datas)}#{funcionamento(regra)}"
    end.first(LIMITE)
  end

  private

  # Quem decide se a regra vale numa data é o MESMO avaliador da agenda, e não uma segunda leitura
  # da recorrência: duas leituras divergem caladas, e aí o retorno anuncia evento em dia que a
  # agenda diz fechado.
  def candidatas
    @excecoes.select { |regra| regra.unit_id == @unidade.id && !regra.feriado? }.sort_by(&:starts_on)
  end

  def rotulo(regra)
    regra.manutencao? ? 'Manutenção na unidade' : 'Evento na unidade'
  end

  # Poucos dias viram lista com o dia da semana; muitos viram intervalo. Um evento de sexta e
  # sábado tem que se ler como sexta e sábado — é assim que a pessoa pensa a semana.
  def periodo(datas)
    return por_extenso(datas.first) if datas.size == 1
    return datas.map { |data| por_extenso(data) }.join(' e ') if datas.size <= 3

    "de #{datas.first.strftime('%d/%m')} a #{datas.last.strftime('%d/%m')}"
  end

  def por_extenso(data)
    "#{DIAS_ABREVIADOS[data.wday]} #{data.strftime('%d/%m')}"
  end

  # Evento que não fecha e não traz horário próprio quer dizer "acontece no horário de sempre" — é
  # o mesmo significado que o cálculo da agenda já dá a esse dado. Dizer isso por extenso, em vez
  # de omitir, é o que separa "o evento é no horário normal" de "não sei que horas é o evento".
  def funcionamento(regra)
    return ', unidade FECHADA nesse período' if regra.closed_all_day?
    return ', no horário de funcionamento de sempre' if regra.open_hour.nil? || regra.close_hour.nil?

    ", das #{relogio(regra.open_hour, regra.open_minutes)} às #{relogio(regra.close_hour, regra.close_minutes)}"
  end

  def relogio(hora, minuto)
    format('%<h>02d:%<m>02d', h: hora, m: minuto.to_i)
  end
end
