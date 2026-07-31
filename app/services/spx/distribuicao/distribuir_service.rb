# Motor de Distribuição (F1) — decide QUAL consultor humano recebe a conversa no
# handoff, quando o time tem política modo=rodizio. Sem política (ou modo off) =
# NO-OP → a conversa segue no fluxo atual ("Aguardando atendimento", pull do dev).
#
# Ordem de decisão (docs/MOTOR-DISTRIBUICAO.md §10.3):
#   0. pool         — filtrado por quem atende o PRODUTO do lead (SPEC-RODIZIO §4 e §7.1).
#                     Sem produto identificado, ou entrada de pool sem `produtos`, nada é filtrado.
#   1. continuidade — contato já atendido por um consultor do pool nos últimos N dias → volta pra ele
#   2. rodízio      — senão, próximo do pool DEPOIS do último (ponteiro em distribuicao_states), pulando cap cheio
#   3. sem_pool     — pool todo indisponível → NÃO atribui (fica aguardando), registra o motivo
#
# Atribui via Conversations::AssignmentService (seta assignee_id humano E solta o
# espelho captain no MESMO save → o concern Enterprise::Concerns::Conversation limpa
# o marcador `aguardando_humano_desde` e registra a auditoria da virada). Logo o
# "aguardando" vira transitório e o SLA passa a contar da atribuição.
module Spx
  module Distribuicao
    class DistribuirService
      Result = Struct.new(:assigned, :user_id, :motivo, keyword_init: true)

      def initialize(conversation)
        @conversation = conversation
        @team = conversation.team
      end

      def call
        return noop unless @team

        policy = Policy.for_team(@conversation.account_id, @team.id)
        return noop if policy.nil? || policy.modo != 'rodizio'

        pool_ids = build_pool(policy) # ordenado: pool ativo ∩ membros atuais do time
        return sem_pool(pool_ids) if pool_ids.empty?

        chosen, motivo = pick(policy, pool_ids)
        return sem_pool(pool_ids) if chosen.nil?

        assign!(chosen)
        advance_state(chosen)
        registrar_log(chosen, motivo, pool_ids)
        Result.new(assigned: true, user_id: chosen, motivo: motivo)
      rescue StandardError => e
        Rails.logger.error("[Distribuicao] conv=#{@conversation&.id} team=#{@team&.id}: #{e.message}")
        noop
      end

      private

      def noop
        Result.new(assigned: false, user_id: nil, motivo: nil)
      end

      def sem_pool(candidatos)
        registrar_log(nil, 'sem_pool', candidatos)
        Result.new(assigned: false, user_id: nil, motivo: 'sem_pool')
      end

      # Interseção pool-configurado ∩ quem atende o PRODUTO do lead ∩ membros atuais do
      # time, PRESERVANDO a ordem do pool (o rodízio anda nessa ordem). cap é aplicado só
      # na hora de escolher.
      def build_pool(policy)
        member_ids = @team.members.pluck(:id).to_set
        policy.pool_entries
              .select { |e| atende_produto?(e) }
              .filter_map { |e| e['user_id']&.to_i }
              .select { |uid| member_ids.include?(uid) }
              .uniq
      end

      # Entrada SEM `produtos` atende TUDO. É o que mantém as políticas já configuradas
      # decidindo exatamente como decidiam antes deste filtro existir — e é também o
      # comportamento certo pra quem é generalista.
      def atende_produto?(entry)
        return true if produto.blank?

        lista = entry['produtos']
        return true if lista.blank?

        Array(lista).any? { |p| p['produto'].to_s == produto }
      end

      # Memoizado com `defined?` porque nil é resposta legítima (lead sem produto
      # identificado) e não pode ser reconsultado a cada entrada do pool.
      #
      # Rescue próprio, e não o do #call: lá em cima uma exceção vira no-op, ou seja,
      # um erro resolvendo produto DESLIGARIA a distribuição do time inteiro em silêncio.
      # Aqui ele degrada pro comportamento anterior (sem filtro), que é o certo.
      def produto
        return @produto if defined?(@produto)

        @produto = ResolverProdutoService.new(@conversation).call
      rescue StandardError => e
        Rails.logger.warn("[Distribuicao] produto conv=#{@conversation&.id}: #{e.message}")
        @produto = nil
      end

      def pick(policy, pool_ids)
        if policy.continuidade_ativa
          anterior = consultor_anterior(policy, pool_ids)
          return [anterior, 'continuidade'] if anterior
        end
        [proximo_rodizio(policy, pool_ids), 'rodizio']
      end

      # Consultor que já atendeu ESTE contato NESTE time, dentro da janela, e que
      # ainda está no pool ativo. Query por contato (índice conversations.contact_id).
      def consultor_anterior(policy, pool_ids)
        desde = policy.continuidade_dias.to_i.days.ago
        @conversation.contact.conversations
                     .where(team_id: @team.id)
                     .where.not(id: @conversation.id)
                     .where(assignee_id: pool_ids)
                     .where('last_activity_at >= ?', desde)
                     .order(last_activity_at: :desc)
                     .limit(1)
                     .pick(:assignee_id)
      end

      # Round-robin: o primeiro do pool DEPOIS do last_user_id (ponteiro no state),
      # pulando quem estourou o cap. Se o último não está mais no pool, começa do início.
      def proximo_rodizio(policy, pool_ids)
        last = State.find_or_initialize_by(team_id: @team.id).last_user_id
        start = pool_ids.index(last)
        ordered = start ? pool_ids.rotate(start + 1) : pool_ids
        ordered.find { |uid| !at_cap?(policy, uid) }
      end

      def cap_for(policy, user_id)
        entry = (policy.pool || []).find { |e| e['user_id'].to_i == user_id }
        cap = entry && entry['cap'].to_i
        cap&.positive? ? cap : nil
      end

      # cap = teto de conversas ABERTAS simultâneas atribuídas ao consultor no time.
      # nil/0 = sem teto.
      def at_cap?(policy, user_id)
        cap = cap_for(policy, user_id)
        return false if cap.nil?

        abertas = @conversation.account.conversations
                               .where(team_id: @team.id, assignee_id: user_id, status: :open)
                               .count
        abertas >= cap
      end

      def assign!(user_id)
        Conversations::AssignmentService.new(conversation: @conversation, assignee_id: user_id).perform
      end

      def advance_state(user_id)
        state = State.find_or_initialize_by(team_id: @team.id)
        state.update!(last_user_id: user_id)
      end

      def registrar_log(user_id, motivo, candidatos)
        Log.create!(account_id: @conversation.account_id, conversation_id: @conversation.id,
                    chosen_user_id: user_id, motivo: motivo, candidatos: candidatos,
                    produto_slug: produto, created_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn("[Distribuicao] log conv=#{@conversation&.id}: #{e.message}")
      end
    end
  end
end
