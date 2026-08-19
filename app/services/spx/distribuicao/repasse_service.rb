# Vence UMA designação parada e passa o lead adiante (SPEC-RODIZIO §7.2, a AÇÃO que faltava).
#
# "Parada" = o Motor escolheu alguém, o prazo de `sla_assumir_minutos` correu em horário de
# expediente e ninguém encostou: nem assumiu no painel, nem respondeu ao cliente, nem engajou no
# card. Até agora isso só virava número na tela do gestor; aqui vira ação.
#
# Três desfechos, nesta ordem:
#   1. PRÓXIMO   — ainda há gente no pool que não queimou a vez neste ciclo e o teto de
#                  `max_repasses` não estourou → repassa (motivo `repasse_sla`).
#   2. GESTOR    — teto estourado, pool esgotado, ou modo fila (que não tem "próximo") →
#                  vai para `pool_esgotado_destino_user_id` (motivo `escalado_gestor`).
#   3. NADA      — sem destino configurado → a designação fica encerrada como `expirado` e a
#                  conversa volta a ficar sem dono. Deliberado: inventar um destino seria pior
#                  que devolver o lead à fila, onde pelo menos ele aparece para todo mundo.
#
# É IDEMPOTENTE por construção: tudo acontece dentro de um lock otimista no próprio log — a
# transição `designado → expirado` só vale uma vez, então o job pode rodar duas vezes sobre a
# mesma linha sem repassar duas vezes.
module Spx
  module Distribuicao
    class RepasseService
      Result = Struct.new(:repassou, :destino, :motivo, keyword_init: true)

      def initialize(log)
        @log = log
      end

      def call
        conversation = @log.conversation
        motivo = impedimento(conversation)
        return desfecho_sem_repasse(motivo) if motivo
        return nada('corrida_perdida') unless expirar!

        repassar(conversation)
      rescue StandardError => e
        Rails.logger.error("[Distribuicao::Repasse] log=#{@log&.id}: #{e.message}")
        nada('erro')
      end

      private

      # O que impede o repasse, ou nil se ele pode acontecer. Devolver o MOTIVO (e não um
      # booleano) é o que deixa o job e o teste explicarem por que um lead não andou.
      def impedimento(conversation)
        return 'log_fechado' unless @log.parada?
        return 'conversa_sumiu' if conversation.nil?

        @policy = Policy.for_team(conversation.account_id, conversation.team_id)
        return 'sem_policy' if @policy.nil? || !@policy.repassa?
        return 'nao_venceu' unless vencido?(conversation)

        'ja_engajada' if engajada?(conversation)
      end

      # Impedimentos que ainda assim FECHAM a linha: a conversa andou por outro caminho, então
      # deixá-la aberta manteria um lead fantasma na conta de "parados" do gestor para sempre.
      ENCERRAM = %w[conversa_sumiu ja_engajada].freeze

      def desfecho_sem_repasse(motivo)
        expirar! if ENCERRAM.include?(motivo)
        nada(motivo)
      end

      def nada(motivo)
        Result.new(repassou: false, destino: nil, motivo: motivo)
      end

      # A transição É a trava: `update_all` com o status no WHERE devolve 0 quando outra
      # execução já venceu a corrida. Devolve true só para quem de fato virou a linha — é o que
      # garante que o mesmo lead não seja repassado duas vezes se o job rodar em duplicata.
      def expirar!
        alterados = Log.where(id: @log.id, status: 'designado')
                       .update_all(status: 'expirado', encerrado_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
        return false if alterados.zero?

        @log.reload
        true
      end

      def vencido?(conversation)
        RelogioComercial.new(conversation.inbox)
                        .vencido?(@log.designado_em, @policy.sla_assumir_minutos)
      end

      # Alguém encostou entre a varredura e agora? No modo assignee o sinal é a primeira
      # resposta humana; nos demais, um dono humano na conversa. O listener normalmente já
      # teria fechado a linha — isto é a rede de segurança para a janela entre as duas coisas.
      def engajada?(conversation)
        return true if conversation.resolved?
        return true if resposta_humana_apos_designacao?(conversation)

        conversation.assignee_id.present? && conversation.assignee_id != @log.chosen_user_id
      end

      def resposta_humana_apos_designacao?(conversation)
        conversation.messages
                    .where(message_type: :outgoing, private: false, sender_type: 'User')
                    .exists?(['messages.created_at > ?', @log.designado_em])
      end

      def repassar(conversation)
        proximo = @policy.esgotou_repasses?(@log.repasse_n) ? nil : distribuir(conversation)
        return Result.new(repassou: true, destino: proximo.user_id, motivo: 'repasse_sla') if proximo&.decidido

        escalar(conversation)
      end

      # Reusa a decisão inteira do Motor (pool, produto, cap, ponteiro do rodízio) em vez de
      # reimplementá-la: só acrescenta quem já queimou a vez neste ciclo e força o motivo.
      def distribuir(conversation)
        return nil if @policy.fila? # fila não tem "próximo" — a espera era de todo mundo

        DistribuirService.new(conversation,
                              excluir: queimados,
                              repasse_n: @log.repasse_n + 1,
                              motivo_forcado: 'repasse_sla').call
      end

      # Todo mundo que já recebeu ESTE lead no ciclo atual. O ciclo começa na designação de
      # `repasse_n = 0` — uma designação nova (re-handoff) zera a conta e o pool volta inteiro.
      def queimados
        Log.where(conversation_id: @log.conversation_id)
           .where('repasse_n <= ?', @log.repasse_n)
           .where.not(chosen_user_id: nil)
           .order(id: :desc)
           .limit(@log.repasse_n + 1)
           .pluck(:chosen_user_id)
           .uniq
      end

      def escalar(conversation)
        destino = @policy.pool_esgotado_destino_user_id
        return nada('sem_destino') if destino.blank?
        return nada('destino_fora_do_time') unless membro_do_time?(conversation, destino)

        Conversations::AssignmentService.new(conversation: conversation, assignee_id: destino).perform
        registrar_escalacao(conversation, destino)
        Result.new(repassou: true, destino: destino, motivo: 'escalado_gestor')
      end

      # O destino tem de ser membro do time, senão `ensure_assignee_is_from_team` (que roda no
      # before_save da conversa) zera a atribuição em silêncio e o lead sumiria de vez.
      def membro_do_time?(conversation, user_id)
        conversation.team&.members&.exists?(id: user_id)
      end

      def registrar_escalacao(conversation, destino)
        Log.create!(account_id: conversation.account_id, conversation_id: conversation.id,
                    chosen_user_id: destino, motivo: 'escalado_gestor', candidatos: [],
                    produto_slug: @log.produto_slug, policy_snapshot: @log.policy_snapshot,
                    repasse_n: @log.repasse_n + 1, status: 'assumido',
                    designado_em: Time.current, encerrado_em: Time.current, created_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn("[Distribuicao::Repasse] log escalacao conv=#{conversation.id}: #{e.message}")
      end
    end
  end
end
