# Quantos minutos de EXPEDIENTE se passaram desde a designação (SPEC-RODIZIO §8.4).
#
# Por que não é relógio de parede: um lead designado 18h50 de sexta estouraria um SLA de 30 min
# às 19h20 de sexta, com o corretor fora — e o gestor veria "não assumiu" de quem estava em casa.
# Medido nas conversas da conta 6, 20 h de parede equivalem a ~4,5 h de expediente; contar na
# parede dispara o repasse na hora errada e a punição cai em quem não tinha como responder.
#
# A fonte do expediente é o `working_hours` da INBOX da conversa (o mesmo que o app usa para o
# out-of-office), então o gestor configura num lugar só. Inbox sem expediente habilitado cai no
# relógio de parede — é o comportamento honesto para quem atende 24/7 e não configurou nada.
module Spx
  module Distribuicao
    class RelogioComercial
      # Granularidade da varredura por dia. O expediente é contínuo dentro de um dia, então
      # percorremos DIA a dia e somamos a interseção do intervalo com a janela daquele dia —
      # nada de laço minuto a minuto.
      MAX_DIAS = 60

      def initialize(inbox)
        @inbox = inbox
      end

      # Minutos de expediente decorridos entre `inicio` e `fim` (default: agora).
      def minutos_decorridos(inicio, fim = Time.current)
        return 0 if inicio.blank? || fim <= inicio
        return ((fim - inicio) / 60).floor unless expediente?

        segundos = 0
        cada_dia(inicio, fim) do |dia|
          janela = janela_do_dia(dia)
          next if janela.nil?

          segundos += sobreposicao(janela, inicio, fim)
        end
        (segundos / 60).floor
      end

      # Já venceu o prazo? Atalho legível para quem só quer o booleano.
      def vencido?(inicio, minutos, fim = Time.current)
        minutos_decorridos(inicio, fim) >= minutos.to_i
      end

      private

      def expediente?
        @inbox.present? && @inbox.working_hours_enabled? && @inbox.working_hours.exists?
      rescue StandardError
        false
      end

      def fuso
        @fuso ||= @inbox.timezone.presence || 'UTC'
      end

      def cada_dia(inicio, fim)
        dia = inicio.in_time_zone(fuso).to_date
        ultimo = fim.in_time_zone(fuso).to_date
        contador = 0
        while dia <= ultimo && contador < MAX_DIAS
          yield dia
          dia += 1
          contador += 1
        end
      end

      # Janela [abre, fecha] daquele dia, no fuso da inbox, ou nil se fechado.
      def janela_do_dia(dia)
        wh = horas_por_dia[dia.wday]
        return nil if wh.nil? || wh.closed_all_day?

        base = dia.in_time_zone(fuso)
        return [base.beginning_of_day, base.end_of_day] if wh.open_all_day?

        [base.change(hour: wh.open_hour, min: wh.open_minutes),
         base.change(hour: wh.close_hour, min: wh.close_minutes)]
      end

      def horas_por_dia
        @horas_por_dia ||= @inbox.working_hours.index_by(&:day_of_week)
      end

      def sobreposicao(janela, inicio, fim)
        abre, fecha = janela
        de = [abre, inicio].max
        ate = [fecha, fim].min
        ate > de ? (ate - de) : 0
      end
    end
  end
end
