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
  end

  private

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
    scope.preload(:team, :inbox, :assignee_agent_bot,
                  contact: { avatar_attachment: [:blob] },
                  assignee: { avatar_attachment: [:blob] })
         .order(last_activity_at: :desc, id: :desc) # o id desempata p/ paginação estável
         .page(@current_page)
         .per(RESULTS_PER_PAGE)
  end

  def set_current_page
    @current_page = params[:page] || 1
  end
end
