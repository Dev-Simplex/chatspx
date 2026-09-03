class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }.merge(unattended_counts)
    }
  end

  # `filter.json.jbuilder` SEMPRE emite as tres chaves `unattended_*`, mas este servico so
  # devolvia quatro contadores — entao elas saiam `null`, enquanto o mesmo campo vem inteiro em
  # `/conversations`. Contador nulo quebra aritmetica em quem consome, e o proprio schema
  # (`conversation_counts`) declara `integer`.
  #
  # "Nao atendida" e a mesma definicao do ConversationFinder: conversa ABERTA que ou nunca teve
  # primeira resposta, ou voltou a esperar (`waiting_since` preenchido) — o escopo `unattended`
  # do modelo.
  def unattended_counts
    nao_atendidas = @conversations.open.unattended
    {
      unattended_assigned_to_me_count: nao_atendidas.assigned_to(@user).count,
      unattended_unassigned_count: nao_atendidas.unassigned.count,
      unattended_all_count: nao_atendidas.count
    }
  end

  def base_relation
    conversations = @account.conversations.includes(
      :taggings, :inbox, { assignee: :avatar_attachment }, { contact: :avatar_attachment }, :team, :contact_inbox
    )

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    @conversations.sort_on_last_activity_at.page(current_page)
  end
end
