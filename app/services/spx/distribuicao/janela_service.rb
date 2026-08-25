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
#   3. nenhuma — devolve nil e o chamador NÃO age
#
# O passo 3 é fail-closed de propósito. Um time sem expediente conhecido é um time sobre o qual
# não sabemos nada; expirar 24/7 faria o lead circular pelo pool de madrugada e aterrissar no
# destino final sem ninguém ver. Recusar agir aparece na tela; agir errado às 3h da manhã não.
module Spx
  module Distribuicao
    class JanelaService
      # Teto de dias que a busca do prazo caminha para a frente. Um time que trabalha 4h por
      # dia e um SLA de 30 min nunca chega perto disso; o limite existe para que expediente
      # mal configurado (todos os dias fechados) termine em nil em vez de girar para sempre.
      MAX_DIAS = 30

      def initialize(policy:, inbox: nil)
        @policy = policy
        @inbox = inbox
      end

      # Existe expediente conhecido? A tela usa isto para avisar que o repasse não vai agir.
      def horario_definido?
        agenda.present?
      end

      # Instante em que o SLA vence, contando só minutos de expediente. nil = sem expediente
      # conhecido (não expira) ou expediente sem nenhum dia aberto.
      def prazo(inicio, minutos)
        return nil if inicio.blank? || minutos.to_i <= 0 || agenda.blank?

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

      def agenda
        return @agenda if defined?(@agenda)

        @agenda = do_policy.presence || da_inbox.presence
      end

      def do_policy
        bruto = @policy&.horario
        return nil unless bruto.is_a?(Hash)

        normalizar(bruto['schedule'])
      end

      # Reaproveita o expediente da inbox quando o operador o ligou de verdade. Desligado, ele
      # carrega os valores default de fábrica do Chatwoot — usá-los seria inventar um horário.
      def da_inbox
        return nil unless @inbox.respond_to?(:working_hours_enabled) && @inbox.working_hours_enabled

        @inbox.working_hours.reject(&:closed_all_day).to_h do |w|
          [w.day_of_week, [[minuto(w.open_hour, w.open_minutes), minuto(w.close_hour, w.close_minutes)]]]
        end.presence
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
