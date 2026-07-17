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
    @requestable_ids = compute_requestable_ids
  end

  private

  # A aba mostra TODOS os atendimentos (D2, p/ dar ciência), mas SOLICITAR só é
  # possível para conversas que o usuário realmente alcança — senão o botão
  # promete uma ação que o backend recusa com 403. Este Set espelha EXATAMENTE a
  # autorização do POST .../takeover_requests (ConversationPolicy#show? +
  # authorize_team_access):
  #   - admin não pede (atribui direto; a policy create? bloqueia) → conjunto vazio;
  #   - precisa de dono HUMANO que não seja eu;
  #   - conversa COM time  → tenho que ser do time (satisfaz o show? por time E o
  #     guard de time de uma vez);
  #   - conversa SEM time  → o guard passa; o show? exige ser membro da CAIXA.
  # Times/caixas do usuário puxados UMA vez; o jbuilder só faz include? no Set.
  def compute_requestable_ids
    user = Current.user
    return Set.new unless user.is_a?(User)
    return Set.new if Current.account_user&.administrator?

    team_ids = user.teams.where(account_id: Current.account.id).pluck(:id).to_set
    inbox_ids = user.inboxes.where(account_id: Current.account.id).pluck(:id).to_set

    @attendances.filter_map { |conv| conv.id if requestable?(conv, user, team_ids, inbox_ids) }.to_set
  end

  def requestable?(conversation, user, team_ids, inbox_ids)
    return false if conversation.assignee_id.blank? || conversation.assignee_agent_bot_id.present?
    return false if conversation.assignee_id == user.id

    if conversation.team_id.present?
      team_ids.include?(conversation.team_id)
    else
      inbox_ids.include?(conversation.inbox_id)
    end
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

  # .to_i: `params[:page] || 1` (o padrão copiado do contacts_controller) devolve a
  # String crua do query string, então meta.current_page saía "2" numa request real
  # e 2 num spec com `as: :json` — tipo instável, e o spec não pegava. O max(1)
  # protege de ?page=abc (→ 0) e de página negativa.
  def set_current_page
    @current_page = [(params[:page] || 1).to_i, 1].max
  end
end
