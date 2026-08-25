# Motor de Distribuição (F1) — decide QUAL consultor humano recebe a conversa no
# handoff, quando o time tem política modo=rodizio. Sem política (ou modo off) =
# NO-OP → a conversa segue no fluxo atual ("Aguardando atendimento", pull do dev).
#
# Ordem de decisão (docs/MOTOR-DISTRIBUICAO.md §10.3):
#   0. pool         — filtrado por quem atende o PRODUTO do lead (SPEC-RODIZIO §4 e §7.1).
#                     Sem produto identificado, ou entrada de pool sem `produtos`, nada é filtrado.
#   1. preferência  — o CLIENTE pediu um corretor pelo nome → vai pra ele, e GASTA a vez dele
#   2. continuidade — contato já atendido por um consultor do pool nos últimos N dias → volta pra
#                     ele, SEM gastar a vez (é retorno, não lead novo)
#   3. rodízio      — senão, próximo do pool DEPOIS do último (ponteiro em distribuicao_states), pulando cap cheio
#   4. sem_pool     — pool todo indisponível → NÃO atribui (fica aguardando), registra o motivo
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

      # Corretor que o CLIENTE pediu pelo nome. Escrito pela conduta da IA, lido aqui.
      PREFERENCIA = 'rodizio_preferencia'.freeze
      # Motivos que gastam a vez do consultor no rodízio (ver #consome_vez?).
      # `repasse_sla` gasta a vez: quem recebeu por repasse recebeu um lead de verdade e tem de
      # andar para o fim da fila igual a todo mundo. Quem DEIXOU vencer já tinha gastado a dele
      # na designação original — é exatamente a "punição aritmética" da SPEC §7.2: o lead conta
      # como recebido, então ao longo do dia quem não responde recebe menos.
      CONSOMEM_VEZ = %w[rodizio preferencia_cliente repasse_sla].freeze

      # `excluir` / `repasse_n` / `motivo_forcado` existem para o REPASSE por SLA
      # (RepasseService) reusar exatamente esta decisão em vez de reimplementá-la:
      #   excluir        — quem já queimou a vez neste ciclo (não pode receber de novo)
      #   repasse_n      — a que altura do ciclo estamos; vai gravado no log e alimenta o teto
      #   motivo_forcado — 'repasse_sla' pula preferência/continuidade. É regra da SPEC §7.2:
      #                    "continuidade é gasta ao expirar" — quem tinha prioridade e deixou
      #                    vencer devolve o lead ao rodízio normal, senão o mesmo consultor
      #                    seria reescolhido pela continuidade e o repasse viraria loop.
      # Defaults preservam o comportamento de sempre para o chamador do handoff.
      def initialize(conversation, excluir: [], repasse_n: 0, motivo_forcado: nil)
        @conversation = conversation
        @team = conversation.team
        @excluir = Array(excluir).compact.to_set(&:to_i)
        @repasse_n = repasse_n.to_i
        @motivo_forcado = motivo_forcado
      end

      def call
        return noop unless @team

        @policy = Policy.for_team(@conversation.account_id, @team.id)
        return noop if @policy.nil? || !@policy.distribui?
        # Modo pull: ninguém é escolhido de propósito. A linha aberta serve só de relógio —
        # é ela que dá à fila o mesmo `sla_assumir_minutos` e a mesma escalação do push.
        return abrir_fila if @policy.fila?

        pool_ids = build_pool(@policy) # ordenado: pool ativo ∩ produto ∩ membros atuais do time
        return sem_pool(pool_ids) if pool_ids.empty?

        chosen, motivo = pick(@policy, pool_ids)
        return sem_pool(pool_ids) if chosen.nil?

        efetivar(chosen, motivo, pool_ids)
      rescue StandardError => e
        Rails.logger.error("[Distribuicao] conv=#{@conversation&.id} team=#{@team&.id}: #{e.message}")
        noop
      end

      private

      def noop
        Result.new(decidido: false, user_id: nil, motivo: nil)
      end

      # Tudo que acontece DEPOIS da escolha, na ordem em que tem de acontecer: a posse, o
      # ponteiro do rodízio, o livro-razão, o carimbo e — por último, porque pode falhar sem
      # invalidar o resto — o espelho no Vista.
      def efetivar(chosen, motivo, pool_ids)
        assign!(chosen)
        advance_state(chosen) if consome_vez?(motivo)
        registrar(chosen, motivo, pool_ids)
        carimbar(chosen)
        espelhar_vista(chosen)
        Result.new(decidido: true, user_id: chosen, motivo: motivo)
      end

      def sem_pool(candidatos)
        registrar(nil, 'sem_pool', candidatos)
        Result.new(decidido: false, user_id: nil, motivo: 'sem_pool')
      end

      # Fila (pull): a conversa fica sem dono, como já ficava sem política nenhuma. A diferença
      # é a linha ABERTA no log — sem ela a espera não tem começo e o SLA não teria de onde
      # contar. `decidido: false` porque ninguém foi escolhido.
      def abrir_fila
        registrar(nil, 'fila', [])
        Result.new(decidido: false, user_id: nil, motivo: 'fila')
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
              .reject { |uid| @excluir.include?(uid) }
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
        # Repasse: direto ao rodízio. Preferência e continuidade apontariam para quem acabou
        # de deixar o prazo vencer (ou para alguém já excluído) e o lead nunca andaria.
        return [proximo_rodizio(policy, pool_ids), @motivo_forcado] if @motivo_forcado

        preferido = preferencia_do_cliente(pool_ids)
        return [preferido, 'preferencia_cliente'] if preferido

        if policy.continuidade_ativa
          anterior = consultor_anterior(policy, pool_ids)
          return [anterior, 'continuidade'] if anterior
        end
        [proximo_rodizio(policy, pool_ids), 'rodizio']
      end

      # O cliente pediu um corretor pelo nome. Quem detecta e registra isso é a CONDUTA DA IA;
      # aqui só se LÊ o campo. Mesma guarda da continuidade: quem não está no pool ativo não
      # recebe, e o lead cai no rodízio normal.
      #
      # Casamento deliberadamente ESTRITO (id, nome completo ou primeiro nome único). Nome
      # ambíguo no pool devolve nil de propósito — mandar o lead pro "Bruno errado" é pior que
      # mandar pro rodízio.
      def preferencia_do_cliente(pool_ids)
        pedido = (@conversation.custom_attributes || {})[PREFERENCIA].to_s.strip.downcase
        return nil if pedido.blank?
        return pedido.to_i if pedido.match?(/\A\d+\z/) && pool_ids.include?(pedido.to_i)

        candidatos = User.where(id: pool_ids).select do |user|
          nome = user.name.to_s.strip.downcase
          nome == pedido || nome.split.first == pedido
        end
        candidatos.size == 1 ? candidatos.first.id : nil
      end

      # Quem GASTA a vez no rodízio é LEAD NOVO.
      #
      # `preferencia_cliente` é lead novo: se não contasse, viraria porta dos fundos — bastava
      # o corretor dizer aos contatos "peça por mim" pra furar a fila inteira, que é justamente
      # o que o rodízio existe pra impedir. Contando, ele recebe o lead E anda pro fim da fila:
      # o pedido do cliente é respeitado e a justiça também.
      #
      # `continuidade` é RETORNO de cliente que já era dele — não é lead novo e não pode gastar
      # a vez de ninguém.
      def consome_vez?(motivo)
        CONSOMEM_VEZ.include?(motivo)
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

      # Espelho no Vista — é como o corretor de vendas fica sabendo do lead. Roda POR ÚLTIMO
      # de propósito: se o Vista estiver fora do ar, a designação já é verdade no SPX (log +
      # carimbo). O próprio serviço checa a flag `espelho_vista` do time.
      def espelhar_vista(user_id)
        VistaCardService.new(conversation: @conversation, policy: @policy,
                             user_id: user_id, produto_slug: produto).perform
      end

      # Uma designação viva por conversa: um re-handoff substitui a anterior, senão a conta
      # de "designados sem movimento" enxergaria a mesma conversa duas vezes.
      def registrar(user_id, motivo, candidatos)
        ciclo_novo = ciclo(user_id)
        # Uma designação viva por conversa. A condição é "a linha NOVA abre uma designação",
        # não "tem gente escolhida": o modo fila abre designação sem `chosen_user_id`, e sem
        # isto duas filas abertas contariam a mesma conversa duas vezes na tela.
        Log.designacao_aberta(@conversation.id)&.encerrar!('substituido') if ciclo_novo[:status] == 'designado'

        Log.create!(account_id: @conversation.account_id, conversation_id: @conversation.id,
                    chosen_user_id: user_id, motivo: motivo, candidatos: candidatos,
                    produto_slug: produto, policy_snapshot: snapshot(candidatos),
                    repasse_n: @repasse_n, created_at: Time.current, **ciclo_novo)
      rescue StandardError => e
        Rails.logger.warn("[Distribuicao] log conv=#{@conversation&.id}: #{e.message}")
      end

      def ciclo(user_id)
        agora = Time.current
        # Fila: ninguém escolhido, mas a espera precisa de início.
        return { status: 'designado', designado_em: agora } if @policy&.fila?
        # `sem_pool` não é designação — é linha de auditoria, nasce sem ciclo de vida.
        return { status: nil } if user_id.blank?
        return { status: 'designado', designado_em: agora } if @policy.designacao?
        # Modo assignee: a posse já é do humano no mesmo instante — a linha nasce e fecha
        # junto, como sempre. EXCETO com repasse ligado: aí "designado" passa a significar
        # "atribuído e ainda sem primeira resposta", que é justamente o estado que o SLA mede.
        # Quem fecha nesse caso é o DesignacaoListener, na primeira resposta humana.
        return { status: 'designado', designado_em: agora } if @policy.repassa?

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
          'continuidade' => { 'ativa' => @policy&.continuidade_ativa, 'dias' => @policy&.continuidade_dias },
          'modo' => @policy&.modo,
          'repasse' => snapshot_repasse
        }
      end

      def snapshot_repasse
        {
          'repassa' => @policy&.repassa?,
          'sla_minutos' => @policy&.sla_assumir_minutos,
          'max' => @policy&.max_repasses,
          'destino_esgotado' => @policy&.pool_esgotado_destino_user_id
        }
      end
    end
  end
end
