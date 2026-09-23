class Api::V1::Accounts::ActiveAttendancesController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 15

  # Uma linha é um ATENDIMENTO (conversa), não um contato: o mesmo contato pode
  # estar em duas conversas abertas, em duas caixas, com dois agentes. Colapsar
  # por contato obrigaria a escolher um agente arbitrário — ou seja, a mentir.
  IN_SERVICE_STATUSES = %i[open pending snoozed].freeze

  before_action :check_authorization
  before_action :set_current_page

  def index
    @attendances = fetch_attendances
    @attendances_count = @attendances.total_count
    @capabilities = compute_capabilities
    @my_pending_requests = fetch_my_pending_requests
    # O chip "2+ abertos" (duplicated) só é lido pela ABA (lista completa). As
    # chamadas escopadas por contato — gate do compose e botão da página de contato
    # — ignoram o campo, então NÃO pagam o GROUP BY/HAVING de conta inteira.
    @duplicated_contact_ids = params[:contact_id].present? ? Set.new : fetch_duplicated_contact_ids
  end

  private

  # Contexto do solicitante puxado UMA vez (2 queries no total, não por linha).
  def requester_context
    @requester_context ||= begin
      user = Current.user
      if user.is_a?(User)
        { user_id: user.id,
          admin: Current.account_user&.administrator? || false,
          team_ids: user.teams.where(account_id: Current.account.id).pluck(:id).to_set,
          inbox_ids: user.inboxes.where(account_id: Current.account.id).pluck(:id).to_set }
      else
        { user_id: nil, admin: false, team_ids: Set.new, inbox_ids: Set.new }
      end
    end
  end

  # A aba mostra TODOS os atendimentos (D2, p/ dar ciência), mas cada linha só pode
  # oferecer a ação que o backend REALMENTE autoriza — senão o botão promete algo
  # que vira 403/422 no clique. Uma capacidade por linha; o jbuilder só lê o hash.
  def compute_capabilities
    ctx = requester_context
    @attendances.each_with_object({}) do |conversation, map|
      map[conversation.id] = {
        open: can_open?(conversation, ctx),
        assume: can_assume?(conversation, ctx),
        request: can_request?(conversation, ctx)
      }
    end
  end

  # "Posso abrir/ver": alcançabilidade por time/inbox + o VETO do isolamento por
  # agente (inbox isolado: conversa de colega não abre, mesmo eu sendo do time).
  # Sem o veto, a aba ofereceria "Abrir"/"Ir para a conversa" que daria 403.
  def can_open?(conversation, ctx)
    return true if ctx[:admin]
    return false if ctx[:user_id].nil?
    return true if conversation.assignee_id == ctx[:user_id]
    return false if isolated_and_foreign?(conversation, ctx)

    reachable?(conversation, ctx)
  end

  # Alcançabilidade pura (espelha authorize_team_access), SEM o veto de isolamento:
  # é a base do pedido — dá pra SOLICITAR uma conversa isolada que eu alcanço pelo
  # time/inbox, mesmo não podendo abri-la.
  def reachable?(conversation, ctx)
    return true if ctx[:admin]
    return false if ctx[:user_id].nil?

    if conversation.team_id.present?
      ctx[:team_ids].include?(conversation.team_id)
    else
      ctx[:inbox_ids].include?(conversation.inbox_id)
    end
  end

  # Regra alcança esta conversa (caixa isolada + time no escopo) + dono humano ≠ eu →
  # não posso abrir (só solicitar). Conversa de time FORA da lista escolhida na caixa não
  # é isolada: a linha volta a oferecer "Abrir". Conversa SEM time continua isolada nesta
  # regra (ela não está em Inbox::TEAMLESS_EXEMPT_RULES) — ver agent_conversation_isolation.rb.
  def isolated_and_foreign?(conversation, ctx)
    inbox = isolated_inboxes[conversation.inbox_id]
    return false unless inbox&.isolation_applies_to_team?(:agent_conversation_isolation, conversation.team_id)

    conversation.assignee_id.present? && conversation.assignee_id != ctx[:user_id]
  end

  # Caixas isoladas da conta indexadas por id, carregadas UMA vez (a capacidade é por linha).
  # `select` enxuto: só o que `isolation_applies_to_team?` lê.
  def isolated_inboxes
    @isolated_inboxes ||= Current.account.inboxes
                                 .where(agent_conversation_isolation: true)
                                 .select(:id, :agent_conversation_isolation, :agent_conversation_isolation_team_ids)
                                 .index_by(&:id)
  end

  # Régua de AÇÃO (pedir/assumir), mais larga que a de ABRIR: a ConversationPolicy#show? já libera
  # por CAIXA *ou* por time — quem barrava conversa de outro time era o guard de time do
  # Conversations::BaseController, afrouxado agora para estes dois caminhos. Oferecer além disto
  # prometeria um 403 no clique.
  def can_act?(conversation, ctx)
    return true if ctx[:admin]
    return false if ctx[:user_id].nil?

    ctx[:inbox_ids].include?(conversation.inbox_id) || ctx[:team_ids].include?(conversation.team_id)
  end

  # "Assumir sem pedir": conversa SEM dono humano (fila ou IA — nos dois casos assignee_id é nil e
  # o AssignmentService troca o bot pelo humano), inclusive a de OUTRO time: é o caso mais comum da
  # fila, e deixá-la sem ação era o beco sem saída da aba. A conversa vem junto com o time de quem
  # puxou (Conversations::TeamHandoverService). Nunca oferece assumir a que já é minha.
  def can_assume?(conversation, ctx)
    return false if ctx[:user_id].nil? || conversation.assignee_id == ctx[:user_id]
    return can_act?(conversation, ctx) if conversation.assignee_id.blank?

    # Dono humano: só admin força; o agente pede (can_request?).
    ctx[:admin]
  end

  # Regra do pedido: só faz sentido com o takeover_request_gate LIGADO — sem a flag a aba não
  # oferece "Solicitar" (degrada p/ "Abrir"/"Bloqueado").
  #
  # Pedir NÃO exige alcance (EA-01): a aba mostra a conta inteira de propósito, e terminar a linha
  # num aviso mudo — "Time comercial, você não participa" — é o beco sem saída que a aba existe
  # para evitar. Pedir não abre conteúdo nenhum: quem libera continua sendo o dono, ao aprovar.
  # O que segue valendo: gate ligado, não ser admin (admin atribui direto), a conversa ter dono
  # HUMANO (de bot não se pede) e o dono não ser eu.
  def can_request?(conversation, ctx)
    return false unless takeover_gate_enabled?
    return false if ctx[:admin] || ctx[:user_id].nil?
    return false if conversation.assignee_id.blank? || conversation.assignee_agent_bot_id.present?

    conversation.assignee_id != ctx[:user_id]
  end

  # Flag da conta puxada UMA vez (a capacidade é calculada por linha).
  def takeover_gate_enabled?
    return @takeover_gate_enabled if defined?(@takeover_gate_enabled)

    @takeover_gate_enabled = Current.account.takeover_request_gate_enabled?
  end

  # Meu pedido pendente por conversa → a linha vira "Pedido enviado · Cancelar".
  # UMA query para a página inteira.
  def fetch_my_pending_requests
    user_id = requester_context[:user_id]
    return {} if user_id.nil?

    ConversationTakeoverRequest.pending
                               .where(requester_id: user_id, conversation_id: @attendances.map(&:id))
                               .pluck(:conversation_id, :id).to_h
  end

  # Contatos com 2+ atendimentos abertos AO MESMO TEMPO — o sintoma exato que a
  # feature existe para matar. Calculado na CONTA INTEIRA (não só na página): as
  # duas conversas do mesmo contato podem cair em páginas diferentes e a duplicação
  # passaria despercebida.
  def fetch_duplicated_contact_ids
    Current.account.conversations
           .where(status: Conversation.statuses.values_at(*IN_SERVICE_STATUSES))
           .where.not(contact_id: nil)
           .group(:contact_id)
           .having('COUNT(*) > 1')
           .pluck(:contact_id)
           .to_set
  end

  # Api::BaseController#check_authorization resolve a policy por
  # controller_name.classify.constantize, e não existe model ActiveAttendance
  # (daria NameError). Molde: funnels_controller#check_authorization.
  def check_authorization
    authorize(:active_attendance)
  end

  # NÃO passa por Conversations::PermissionFilterService, de propósito.
  # Aquele filtro protege CONTEÚDO de conversa, e aqui não sai um byte de
  # mensagem — só metadado (contato, agente, time, caixa, status, tempo). É o
  # mesmo grau de exposição da aba "Todos os contatos", que já lista a conta
  # inteira. Aplicá-lo quebraria o requisito ("atendimento geral": o agente
  # precisa enxergar que OUTRO time já atende o contato — é justamente essa
  # cegueira que causa o atendimento duplicado) e devolveria lista incompleta em
  # silêncio. A spec do controller trava isso: agente de outro time VÊ.
  def fetch_attendances
    scope = Current.account.conversations
                   .where(status: Conversation.statuses.values_at(*IN_SERVICE_STATUSES))
                   .where.not(contact_id: nil)
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    scope = filtrar_por_busca(scope)

    # preload, NÃO includes: `includes` + `order` vira LEFT JOIN e quebra o total_count.
    # O avatar do assignee_agent_bot também entra: o jbuilder chama bot.avatar_url,
    # que sem isto custa +1 query por bot DISTINTO na página.
    scope.preload(:team, :inbox,
                  contact: { avatar_attachment: [:blob] },
                  assignee: { avatar_attachment: [:blob] },
                  assignee_agent_bot: { avatar_attachment: [:blob] })
         .order(last_activity_at: :desc, id: :desc) # o id desempata p/ paginação estável
         .page(@current_page)
         .per(RESULTS_PER_PAGE)
  end

  # A busca da aba precisa acontecer AQUI, antes de paginar: a tela tem 15 das 99 linhas na mão, e
  # filtrar o que já está carregado diria "não achei" sobre as outras 84 — a resposta errada numa
  # tela que existe para evitar atendimento duplicado.
  #
  # `joins`, nunca `includes`: `includes` + `order` vira LEFT JOIN e quebra o total_count (a mesma
  # armadilha anotada em fetch_attendances). O assignee é left_joins porque a conversa pode estar
  # na fila, sem agente.
  def filtrar_por_busca(scope)
    termo = params[:q].to_s.strip
    return scope if termo.length < 2

    escopo = scope.joins(:contact).left_joins(:assignee)
    digitos = termo.gsub(/\D/, '')

    # Telefone digitado com máscara: quem copia do painel cola "(66) 99927-4845" e o banco guarda
    # "+5566999274845" — o ILIKE cru não casa. Termo só de dígitos e pontuação vira comparação de
    # dígitos contra o telefone sem pontuação. Um campo, duas estratégias.
    if digitos.length >= 3 && termo.match?(/\A[\d\s()+.\-]+\z/)
      return escopo.where("regexp_replace(contacts.phone_number, '\\D', '', 'g') LIKE :digitos",
                          digitos: "%#{digitos}%")
    end

    like = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    escopo.where(
      'contacts.name ILIKE :q OR contacts.email ILIKE :q OR contacts.phone_number ILIKE :q ' \
      'OR contacts.identifier ILIKE :q OR users.name ILIKE :q',
      q: like
    )
  end

  # .to_i: `params[:page] || 1` (o padrão copiado do contacts_controller) devolve a
  # String crua do query string, então meta.current_page saía "2" numa request real
  # e 2 num spec com `as: :json` — tipo instável, e o spec não pegava. O max(1)
  # protege de ?page=abc (→ 0) e de página negativa.
  def set_current_page
    @current_page = [(params[:page] || 1).to_i, 1].max
  end
end
