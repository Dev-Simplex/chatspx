# O relógio do SLA, que anda só dentro do expediente do time.
#
# Sem isto, todo lead que chega numa sexta 17h50 nasce estourado na segunda de manhã, e o
# repasse pune quem estava legitimamente fora do trabalho.
#
# Em vez de "quantos minutos úteis já passaram?", calcula O PRAZO: a partir de `de`, caminha
# para a frente consumindo minutos abertos até esgotar o SLA. Dá na mesma matematicamente e é
# muito melhor de explicar — a tela pode dizer "vence às 14:20" em vez de um contador.
#
# Fonte do expediente, nesta ordem:
#   1. `policy.horario` — o expediente do time, configurado na tela
#   2. `inbox.working_hours` — só se `working_hours_enabled`, para reaproveitar o que já existe
#   3. nenhuma — decidido pelo CHAMADOR, via `sem_agenda:`
#
# Sem agenda em lugar nenhum, os dois chamadores precisam de coisas OPOSTAS, e por isso a escolha
# é explícita em vez de embutida aqui:
#
#   `:nao_vence` (default, modo `assignee`/locação) — fail-closed. Um time sem expediente
#   conhecido é um time sobre o qual não sabemos nada; expirar 24/7 faria o lead circular pelo
#   pool de madrugada e aterrissar no destino final sem ninguém ver. Recusar agir aparece na
#   tela; agir errado às 3h da manhã não. É como este serviço nasceu no PR #67.
#
#   `:parede` (modo `designacao`/vendas) — relógio de parede. NÃO é preferência de desenho, é
#   PRESERVAÇÃO: o repasse de vendas está em produção desde 19/08 com o antigo RelogioComercial,
#   que caía no relógio de parede quando a caixa não tinha expediente. Unificar os dois relógios
#   adotando o default fail-closed desligaria o repasse EM SILÊNCIO em todo time sem expediente
#   configurado — a correção apagaria a funcionalidade que ela veio consertar.
module Spx
  module Distribuicao
    class JanelaService
      # Teto de dias que a busca do prazo caminha para a frente. Um time que trabalha 4h por
      # dia e um SLA de 30 min nunca chega perto disso; o limite existe para que expediente
      # mal configurado (todos os dias fechados) termine em nil em vez de girar para sempre.
      MAX_DIAS = 30

      SEM_AGENDA = %i[nao_vence parede].freeze

      def initialize(policy:, inbox: nil, sem_agenda: :nao_vence)
        raise ArgumentError, "sem_agenda invalido: #{sem_agenda.inspect}" unless SEM_AGENDA.include?(sem_agenda)

        @policy = policy
        @inbox = inbox
        @sem_agenda = sem_agenda
      end

      # Existe expediente conhecido? A tela usa isto para avisar que o repasse não vai agir.
      def horario_definido?
        agenda.present?
      end

      # Instante em que o SLA vence, contando só minutos de expediente. nil = sem expediente
      # conhecido (não expira) ou expediente sem nenhum dia aberto.
      def prazo(inicio, minutos)
        return nil if inicio.blank? || minutos.to_i <= 0

        # `sla_respeita_horario` desligado: relogio de PAREDE. Sem isto a coluna era gravada
        # pela tela e por ninguem lida — um checkbox que nao fazia nada. Note que aqui o
        # fail-closed de agenda ausente nao se aplica: quem desligou o respeito ao expediente
        # pediu 24/7 explicitamente, entao nao ter agenda deixa de ser motivo para nao agir.
        return inicio + minutos.to_i.minutes if @policy && !@policy.sla_respeita_horario

        return sem_agenda_prazo(inicio, minutos) if agenda.nil?

        restante = minutos.to_i
        cursor = inicio.in_time_zone(fuso)

        MAX_DIAS.times do
          vencimento, restante = consumir_dia(cursor, restante)
          return vencimento if vencimento

          cursor = (cursor + 1.day).beginning_of_day
        end

        nil
      end

      # Já venceu? Falso quando não há prazo — sem expediente conhecido, nada expira.
      def vencido?(inicio, minutos, agora = Time.current)
        limite = prazo(inicio, minutos)
        limite.present? && agora >= limite
      end

      private

      # Sem expediente conhecido em lugar nenhum: quem decide é o chamador (ver o cabeçalho).
      def sem_agenda_prazo(inicio, minutos)
        return nil if @sem_agenda == :nao_vence

        inicio + minutos.to_i.minutes
      end

      # Consome o expediente do dia do cursor. Devolve [vencimento, restante]; com vencimento
      # preenchido, o SLA acabou dentro deste dia.
      def consumir_dia(cursor, restante)
        faixas_do_dia(cursor).each do |abre, fecha|
          next if fecha <= cursor

          entrada = [cursor, abre].max
          disponivel = ((fecha - entrada) / 60).floor
          return [entrada + (restante * 60), 0] if disponivel >= restante

          restante -= disponivel
        end
        [nil, restante]
      end

      # TRÊS estados, e a diferença entre os dois últimos é o que impede punir quem estava
      # legitimamente fora do trabalho:
      #
      #   nil  — NENHUMA fonte configurada. Não sabemos nada; quem decide é o `sem_agenda`.
      #   {}   — fonte CONFIGURADA e sempre fechada (todos os dias marcados como fechados). O
      #          expediente é conhecido: é "nunca". Então nada vence, e isso NÃO é caso de
      #          `sem_agenda` — o operador respondeu, e a resposta foi "este time não atende".
      #   hash — expediente com faixas abertas.
      #
      # Colapsar {} em nil (que é o que `.presence` fazia) faria o time que marcou todos os dias
      # como fechados cair no relógio de parede e ver seus leads repassados de madrugada.
      def agenda
        return @agenda if defined?(@agenda)

        @agenda = do_policy || da_inbox
      end

      # `horario` nasce `{}` (jsonb default, null: false), então a coluna existir não quer dizer
      # que alguém configurou: o sinal de "configurado" é ter `schedule`.
      def do_policy
        bruto = @policy&.horario
        return nil unless bruto.is_a?(Hash) && bruto['schedule'].present?

        normalizar(bruto['schedule']) || {}
      end

      # Reaproveita o expediente da inbox quando o operador o ligou de verdade. Desligado, ele
      # carrega os valores default de fábrica do Chatwoot — usá-los seria inventar um horário.
      # Ligado mas com todos os dias fechados devolve `{}`, e não nil: ver #agenda.
      def da_inbox
        return nil unless @inbox.respond_to?(:working_hours_enabled) && @inbox.working_hours_enabled
        return nil unless @inbox.working_hours.exists?

        @inbox.working_hours.reject(&:closed_all_day).to_h do |w|
          [w.day_of_week, [[minuto(w.open_hour, w.open_minutes), minuto(w.close_hour, w.close_minutes)]]]
        end
      end

      # { dia_da_semana => [[minuto_inicial, minuto_final], ...] }, minutos desde a meia-noite.
      def normalizar(schedule)
        return nil unless schedule.is_a?(Array)

        schedule.each_with_object({}) do |dia, mapa|
          faixas = faixas_validas(dia['ranges'])
          mapa[dia['day'].to_i] = faixas if faixas.any?
        end.presence
      end

      # Faixa sem hora legível, ou que fecha antes de abrir, é descartada em silêncio: o dia
      # perde aquela janela em vez de o expediente inteiro virar inválido.
      def faixas_validas(ranges)
        Array(ranges).filter_map do |r|
          abre = parse_hora(r['start'])
          fecha = parse_hora(r['end'])
          [abre, fecha] if abre && fecha && fecha > abre
        end.sort_by(&:first)
      end

      def parse_hora(texto)
        h, m = texto.to_s.split(':')
        return nil if h.blank?

        minuto(h.to_i, m.to_i)
      end

      def minuto(hora, minutos)
        (hora.to_i * 60) + minutos.to_i
      end

      def fuso
        (@policy&.horario.is_a?(Hash) && @policy.horario['timezone'].presence) || Time.zone.name
      end

      # Faixas do dia do cursor, já como instantes.
      def faixas_do_dia(cursor)
        meia_noite = cursor.beginning_of_day
        Array(agenda[cursor.wday]).map do |inicio, fim|
          [meia_noite + inicio.minutes, meia_noite + fim.minutes]
        end
      end
    end
  end
end
