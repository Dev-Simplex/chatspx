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
# O que acontece com a POSSE depois da escolha depende de `policy.modo_posse`:
#
#   assignee   — atribui via Conversations::AssignmentService (seta assignee_id humano E
#                solta o espelho captain no MESMO save → o concern
#                Enterprise::Concerns::Conversation limpa o marcador
#                `aguardando_humano_desde` e registra a auditoria da virada). O
#                "aguardando" vira transitório e o SLA conta da atribuição.
#
#   designacao — NÃO toca em assignee. A escolha vira uma linha ABERTA no Log
#                (status=designado) e nada mais: o espelho captain sobrevive e a IA
#                continua atendendo até alguém assumir de fato. É o terceiro estado da
#                SPEC-RODIZIO §3, e existe porque em vendas o corretor não vive no SPX —
#                gravar `assignee` ali seria mentir no dado e calar a IA à toa.
module Spx
  module Distribuicao
    class DistribuirService
      # `decidido` = o Motor escolheu um responsável. NÃO quer dizer que houve atribuição:
      # em modo_posse=designacao ninguém vira `assignee` (ver #assign!).
      Result = Struct.new(:decidido, :user_id, :motivo, keyword_init: true)

      def initialize(conversation)
        @conversation = conversation
        @team = conversation.team
      end

      def call
        return noop unless @team

        @policy = Policy.for_team(@conversation.account_id, @team.id)
        return noop if @policy.nil? || @policy.modo != 'rodizio'

        pool_ids = build_pool(@policy) # ordenado: pool ativo ∩ produto ∩ membros atuais do time
        return sem_pool(pool_ids) if pool_ids.empty?

        chosen, motivo = pick(@policy, pool_ids)
        return sem_pool(pool_ids) if chosen.nil?

        assign!(chosen)
        advance_state(chosen)
        registrar(chosen, motivo, pool_ids)
        carimbar(chosen)
        Result.new(decidido: true, user_id: chosen, motivo: motivo)
      rescue StandardError => e
        Rails.logger.error("[Distribuicao] conv=#{@conversation&.id} team=#{@team&.id}: #{e.message}")
        noop
      end

      private

      def noop
        Result.new(decidido: false, user_id: nil, motivo: nil)
      end

      def sem_pool(candidatos)
        registrar(nil, 'sem_pool', candidatos)
        Result.new(decidido: false, user_id: nil, motivo: 'sem_pool')
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
      #
      # ⚠️ Em modo_posse=designacao isto naturalmente não casa: `assignee` nunca é gravado,
      # então não há histórico por onde procurar. NÃO é bug — em vendas a fonte de "quem já
      # atende este cliente" é o VISTA (SPEC-RODIZIO §7.1), e entra junto com o espelho.
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

      # Em modo_posse=designacao NÃO tocamos em `assignee`. É exatamente isso que mantém o
      # espelho captain vivo (o callback de exclusividade nunca dispara) e a IA atendendo
      # até alguém assumir de fato — o terceiro estado da SPEC-RODIZIO §3.
      # Em modo assignee, comportamento de sempre: atribui e a IA cala.
      def assign!(user_id)
        return if @policy.designacao?

        Conversations::AssignmentService.new(conversation: @conversation, assignee_id: user_id).perform
      end

      def advance_state(user_id)
        state = State.find_or_initialize_by(team_id: @team.id)
        state.update!(last_user_id: user_id)
      end

      # Só em designacao: no modo assignee o painel já mostra o dono, e o carimbo seria ruído.
      # Aqui ele é necessário — é o único sinal de que a conversa tem dono.
      def carimbar(user_id)
        return unless @policy.designacao?

        CarimbarService.new(conversation: @conversation, user_id: user_id, produto: produto).perform
      end

      # Uma designação viva por conversa: um re-handoff substitui a anterior, senão a conta
      # de "designados sem movimento" enxergaria a mesma conversa duas vezes.
      def registrar(user_id, motivo, candidatos)
        Log.designacao_aberta(@conversation.id)&.encerrar!('substituido') if user_id.present?

        Log.create!(account_id: @conversation.account_id, conversation_id: @conversation.id,
                    chosen_user_id: user_id, motivo: motivo, candidatos: candidatos,
                    produto_slug: produto, policy_snapshot: snapshot(candidatos),
                    created_at: Time.current, **ciclo(user_id))
      rescue StandardError => e
        Rails.logger.warn("[Distribuicao] log conv=#{@conversation&.id}: #{e.message}")
      end

      # `sem_pool` não é designação — é linha de auditoria, nasce sem ciclo de vida.
      # Em modo assignee a posse já é do humano no mesmo instante: nasce e fecha junto.
      def ciclo(user_id)
        return { status: nil } if user_id.blank?

        agora = Time.current
        return { status: 'designado', designado_em: agora } if @policy.designacao?

        { status: 'assumido', designado_em: agora, encerrado_em: agora }
      end

      # A regra que valeu NESTA decisão, inteira. Quando o gestor mudar o pool amanhã, a
      # tela ainda precisa saber explicar a escolha de ontem.
      def snapshot(candidatos)
        {
          'modo_posse' => @policy&.modo_posse,
          'produto' => produto,
          'pool_elegivel' => candidatos,
          'pool_configurado' => @policy&.pool,
          'continuidade' => { 'ativa' => @policy&.continuidade_ativa, 'dias' => @policy&.continuidade_dias }
        }
      end
    end
  end
end
