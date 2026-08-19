# Varre as designações paradas e enfileira o repasse de cada uma (SPEC-RODIZIO §7.2).
#
# Roda a cada 5 min. O filtro em duas etapas é de propósito:
#   1. GROSSO, no banco — `status = 'designado' AND designado_em <= agora - menor_sla`, usando o
#      índice (status, designado_em) que já existe. Traz poucas dezenas de linhas mesmo numa
#      instância grande.
#   2. FINO, em memória — o prazo de verdade é conferido pelo RelogioComercial, política por
#      política, dentro do RepasseService. Conferir expediente na query exigiria replicar o
#      calendário em SQL; conferir sobre a tabela inteira seria caro. Sobre dezenas de linhas
#      é barato e fica num lugar só.
#
# Só olha políticas com `repasse_automatico` LIGADO. Quem usa o SLA apenas como medida (a conta
# 6, e qualquer política nova, já que o default é false) nunca é tocado por este job.
module Spx
  module Distribuicao
    class VarrerSlaJob < ApplicationJob
      queue_as :scheduled_jobs

      # Teto por rodada: se algo represar (fila parada, mudança de configuração que vence mil
      # designações de uma vez), o estrago sai em lotes e não numa avalanche de atribuições.
      LOTE = 200

      def perform
        policies = Policy.ativas.where(repasse_automatico: true)
        return if policies.empty?

        menor_sla = policies.minimum(:sla_assumir_minutos).to_i
        return if menor_sla <= 0

        candidatas(policies, menor_sla).find_each(batch_size: 50) do |log|
          RepassarJob.perform_later(log.id)
        end
      end

      private

      # `designado_em` no relógio de PAREDE com o MENOR sla de todas as políticas: é o limite
      # inferior seguro — nenhuma designação pode ter vencido em horário comercial antes de
      # ter vencido na parede. O RepasseService descarta as que ainda não venceram de fato.
      def candidatas(policies, menor_sla)
        Log.designadas_antes_de(menor_sla.minutes.ago)
           .where(account_id: policies.select(:account_id))
           .order(:designado_em)
           .limit(LOTE)
      end
    end
  end
end
