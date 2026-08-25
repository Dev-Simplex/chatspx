# Repasse por SLA: o lead que ninguém tocou dentro do prazo vai para o próximo do pool.
#
# Até aqui o `sla_assumir_minutos` só MEDIA — a tela mostrava "12 leads parados há mais de 2h"
# e nada acontecia. Este job é o que transforma o número em ação, e ele age **só** onde o
# operador ligou `repasse_automatico` (que nasce false).
#
# ⚠️ O SLA quer dizer coisas DIFERENTES nos dois modos de posse, e é por isso que há dois
# caminhos aqui em vez de um:
#
#   designacao (vendas) — ninguém é dono ainda. A linha aberta no livro-razão É o estado
#                         "designado", e o SLA mede **não assumiu**.
#   assignee (locação)  — a pessoa já é a dona no instante da escolha (o `ciclo` do
#                         DistribuirService nasce e fecha o log junto). Não há o que expirar;
#                         o SLA mede **não respondeu ao cliente**.
#
# Tratar os dois como o mesmo relógio faria o job nunca agir em locação — que é justamente o
# time onde ele vai ser ligado primeiro.
module Spx
  module Distribuicao
    class RepasseJob < ApplicationJob
      queue_as :scheduled_jobs

      # Janela de varredura. Conversa parada há mais de uma semana não é problema de
      # distribuição — é problema de gestão, e repassá-la agora só criaria ruído.
      LOOKBACK = 7.days

      def perform
        Policy.ativas.where(modo: 'rodizio', repasse_automatico: true).find_each do |policy|
          processar(policy)
        rescue StandardError => e
          Rails.logger.error("[RepasseJob] policy=#{policy.id}: #{e.class}: #{e.message}")
        end
      end

      private

      def processar(policy)
        pendentes(policy).each { |log| avaliar(log, policy) }
      end

      def pendentes(policy)
        escopo = Log.where(account_id: policy.account_id, conversation_id: conversas_abertas(policy))
                    .where(designado_em: LOOKBACK.ago..)
        return escopo.abertas.to_a if policy.designacao?

        escopo.where(status: 'assumido').select { |log| sem_resposta?(log) }
      end

      def conversas_abertas(policy)
        Conversation.where(account_id: policy.account_id, team_id: policy.team_id, status: :open).select(:id)
      end

      # Em modo assignee: a pessoa continua sendo a dona e ainda não falou com o cliente desde
      # que recebeu. Se ela já respondeu, não há SLA nenhum a cobrar.
      def sem_resposta?(log)
        conv = log.conversation
        return false if conv.nil? || conv.assignee_id != log.chosen_user_id

        !conv.messages.exists?(
          sender_type: 'User', sender_id: log.chosen_user_id,
          message_type: :outgoing, private: false, created_at: log.designado_em..
        )
      end

      def avaliar(log, policy)
        conv = log.conversation
        return if conv.blank?

        janela = JanelaService.new(policy: policy, inbox: conv.inbox)
        # Sem expediente conhecido o prazo é nil e NADA vence — de propósito. Ver JanelaService.
        return unless janela.vencido?(log.designado_em, policy.sla_assumir_minutos)

        repassar(log, policy, conv)
      end

      def repassar(log, policy, conv)
        tentados = tentados(conv)
        esgotou = esgotou?(conv, policy)
        log.encerrar!('expirado')

        destino = esgotou ? policy.pool_esgotado_destino_user_id : proximo(policy, conv, tentados)
        return registrar(policy, conv, nil, 'sem_pool', tentados) if destino.blank?

        aplicar(policy, conv, destino)
        registrar(policy, conv, destino, esgotou ? 'pool_esgotado' : 'repasse', tentados)
        # O destino final não faz parte da sequência do rodízio: ele é rede, não vez.
        avancar_ponteiro(policy, destino) unless esgotou
      end

      def tentados(conv)
        Log.where(conversation_id: conv.id).where.not(chosen_user_id: nil).distinct.pluck(:chosen_user_id)
      end

      def esgotou?(conv, policy)
        Log.where(conversation_id: conv.id, status: 'expirado').count + 1 >= policy.max_repasses.to_i
      end

      # Próximo do pool que ainda não recebeu ESTA conversa. Reusar o DistribuirService aqui
      # seria errado: a cascata dele começa por continuidade, que devolveria justamente quem
      # acabou de deixar vencer.
      def proximo(policy, conv, tentados)
        elegiveis(policy).find { |uid| tentados.exclude?(uid) && !no_teto?(policy, conv, uid) }
      end

      # Pool disponível ∩ membros atuais do time — a mesma interseção do build_pool, porque
      # quem não é membro nunca receberia de qualquer forma.
      def elegiveis(policy)
        membros = Team.find_by(id: policy.team_id)&.members&.pluck(:id).to_a
        policy.pool_entries.filter_map { |e| e['user_id']&.to_i }.select { |uid| membros.include?(uid) }
      end

      def no_teto?(policy, conv, user_id)
        entrada = policy.pool.find { |e| e.is_a?(Hash) && e['user_id'].to_i == user_id }
        teto = entrada && entrada['cap'].to_i
        return false unless teto&.positive?

        Conversation.where(account_id: conv.account_id, team_id: policy.team_id,
                           assignee_id: user_id, status: :open).count >= teto
      end

      def aplicar(policy, conv, user_id)
        return if policy.designacao?

        Conversations::AssignmentService.new(conversation: conv, assignee_id: user_id).perform
      end

      def avancar_ponteiro(policy, user_id)
        State.find_or_initialize_by(team_id: policy.team_id).update!(last_user_id: user_id)
      end

      # `expirado_conta_como_recebido` NÃO é consumido aqui de propósito: a linha `expirado`
      # fica no livro-razão com o nome de quem deixou vencer, e quem decide se ela conta é a
      # TELA de contabilização. O job não pode apagar histórico para satisfazer uma opção de
      # exibição — por isso o valor vai no snapshot, para a tela saber o que valia na hora.
      def registrar(policy, conv, user_id, motivo, candidatos)
        Log.create!(
          account_id: conv.account_id, conversation_id: conv.id, chosen_user_id: user_id,
          motivo: motivo, candidatos: candidatos, created_at: Time.current,
          policy_snapshot: { 'origem' => 'repasse_sla',
                             'sla_minutos' => policy.sla_assumir_minutos,
                             'max_repasses' => policy.max_repasses,
                             'expirado_conta_como_recebido' => policy.expirado_conta_como_recebido },
          **ciclo(policy, user_id)
        )
      rescue StandardError => e
        Rails.logger.warn("[RepasseJob] log conv=#{conv&.id}: #{e.message}")
      end

      def ciclo(policy, user_id)
        return { status: nil } if user_id.blank?

        agora = Time.current
        return { status: 'designado', designado_em: agora } if policy.designacao?

        { status: 'assumido', designado_em: agora, encerrado_em: agora }
      end
    end
  end
end
