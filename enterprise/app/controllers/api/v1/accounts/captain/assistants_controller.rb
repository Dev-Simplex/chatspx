class Api::V1::Accounts::Captain::AssistantsController < Api::V1::Accounts::BaseController
  include Captain::ApiKeyValidation

  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_assistant, only: [:show, :update, :destroy, :playground, :stats]
  before_action :ensure_captain_api_key!, only: :playground

  def index
    @assistants = account_assistants.includes(:agent_bot, :captain_inboxes).ordered
  end

  def show; end

  def create
    @assistant = account_assistants.create!(assistant_params)
  end

  def update
    @assistant.update!(update_params)
  end

  def destroy
    @assistant.destroy
    head :no_content
  end

  def playground
    response = if captain_v2_enabled?
                 Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'playground').generate_response(
                   message_history: playground_message_history
                 )
               else
                 Captain::Llm::AssistantChatService.new(assistant: @assistant, source: 'playground').generate_response(
                   additional_message: playground_params[:message_content],
                   message_history: message_history
                 )
               end

    render json: response
  end

  def tools
    assistant = Captain::Assistant.new(account: Current.account)
    @tools = assistant.available_agent_tools
  end

  # Métricas REAIS do assistant (aditivo). Tudo defensivo: nunca 500.
  #
  # A fonte NÃO pode ser `assignee_agent_bot_id` (o dono ATUAL da conversa): o handoff LIMPA esse
  # campo quando a IA entrega o atendimento para um humano. Com ele o painel era um retrato
  # instantâneo, não um acumulado, e sumia com quase tudo que a IA atendeu. Medido em produção
  # (Tozi): Clara 182 contra 2158 conversas, Bruna 8 contra 916, e Letícia/Marina/Rafa/Helena
  # apareciam com ZERO tendo 54/71/41/3. O CSAT dava 0.0 nos 12 agentes das duas contas pelo
  # mesmo motivo: quando a pesquisa é respondida a conversa já saiu do bot. E como `resolved`
  # dava 0 em 11 dos 12, a "taxa de resolução" grande no topo da tela era 0% para quase todos.
  #
  # Fonte correta: captain_assistant_logs, a trilha de toda atuação do assistente na conversa
  # (index_captain_assistant_logs_on_captain_assistant_id já existe; a semi-junção custa ~9 ms
  # no maior assistente de produção). O conjunto das conversas hoje atribuídas ao mirror bot
  # entra junto (UNION) para que a troca nunca SUBTRAIA do que o painel já mostrava: conversa
  # atribuída antes de a tabela de logs existir não tem linha lá. É um superconjunto do antigo.
  #
  # A forma do JSON não muda: OverviewTab.vue lê handled, resolved, resolution_rate, csat,
  # handoffs e series com esses nomes e esses tipos.
  def stats
    base = assistant_conversations
    handled = safe_count(base)
    resolved = safe_count(base.where(status: :resolved))
    @stats = {
      handled: handled,
      resolved: resolved,
      resolution_rate: handled.zero? ? 0 : (resolved * 100.0 / handled).round,
      csat: assistant_csat,
      handoffs: assistant_handoffs(base),
      series: assistant_series(base)
    }
  end

  private

  # Conversas em que este assistente DE FATO atuou, independente de quem é o dono hoje.
  def assistant_conversations
    Conversation.where(account_id: Current.account.id)
                .where("conversations.id IN (#{assistant_conversation_ids_sql})")
  rescue StandardError
    Conversation.none
  end

  # UNION e não OR, e é medido: `id IN (logs) OR assignee_agent_bot_id = bot` faz o Postgres
  # varrer TODAS as conversas da conta e filtrar (15,5 ms varrendo 10.814 linhas na conta 6, e
  # o custo cresce com o tamanho da CONTA). Com UNION ele monta o conjunto de ids pelos dois
  # índices (index_captain_assistant_logs_on_captain_assistant_id e o parcial
  # idx_conv_assignee_agent_bot_id) e faz semi-junção pela PK: 1,05 ms, e o custo cresce com
  # as conversas DO ASSISTENTE, não com a conta. EXPLAIN ANALYZE dos dois no relatório da T4.
  #
  # Subconsulta e não array: carregar os ids em memória seria um N+1 disfarçado (o maior
  # assistente de produção tem 2158 conversas em 9746 linhas de log). Interpolar `to_sql` aqui
  # é seguro: os dois únicos valores são ids inteiros vindos do banco, não do request.
  def assistant_conversation_ids_sql
    @assistant_conversation_ids_sql ||= build_assistant_conversation_ids_sql
  end

  def build_assistant_conversation_ids_sql
    logged = Captain::AssistantLog.where(captain_assistant_id: @assistant.id)
                                  .where.not(conversation_id: nil)
                                  .select(:conversation_id)
    bot = @assistant.agent_bot
    return logged.to_sql if bot.blank?

    "#{logged.to_sql} UNION #{Conversation.where(assignee_agent_bot_id: bot.id).select(:id).to_sql}"
  end

  def safe_count(scope)
    scope.count
  rescue StandardError
    0
  end

  # Vai direto no mesmo conjunto de ids em vez de aninhar a consulta de conversas dentro da de
  # respostas (metade do tempo de planejamento, medido). Dá no mesmo: a conta já está filtrada
  # aqui e a resposta de CSAT é apagada junto com a conversa.
  def assistant_csat
    CsatSurveyResponse.where(account_id: Current.account.id)
                      .where("csat_survey_responses.conversation_id IN (#{assistant_conversation_ids_sql})")
                      .average(:rating).to_f.round(1)
  rescue StandardError
    0.0
  end

  def assistant_handoffs(base)
    base.where("conversations.custom_attributes ->> 'aguardando_humano_desde' IS NOT NULL").count
  rescue StandardError
    0
  end

  def assistant_series(base)
    by_day = base.where(conversations: { created_at: 6.days.ago.beginning_of_day..Time.current.end_of_day })
                 .group(Arel.sql('DATE(conversations.created_at)')).count
    (0..6).map do |i|
      d = i.days.ago.to_date
      { date: d.to_s, count: (by_day[d] || by_day[d.to_s] || 0).to_i }
    end.reverse
  rescue StandardError
    []
  end

  def set_assistant
    @assistant = account_assistants.find(params[:id])
  end

  def account_assistants
    @account_assistants ||= Captain::Assistant.for_account(Current.account.id)
  end

  # `config` é jsonb: `update!` SUBSTITUI o hash inteiro, não mescla. Junte isso a um
  # strong params de lista fechada e QUALQUER save pela tela apagava calado as chaves de
  # config fora da lista (team_id, triage, voice_id, fotos_carrossel...). Aqui o payload
  # entra POR CIMA do config já gravado, então o que não foi editado permanece.
  #
  # Efeito colateral aceito: pela tela dá para sobrescrever uma chave de config, mas não
  # mais para APAGAR uma (mandar o config sem ela não a remove). Nenhuma tela faz isso hoje.
  def update_params
    permitted = assistant_params
    return permitted unless permitted.key?(:config)

    permitted.merge(config: @assistant.config.to_h.merge(permitted[:config].to_h))
  end

  def assistant_params
    permitted = params.require(:assistant).permit(:name, :description,
                                                  config: [
                                                    :product_name, :feature_faq, :feature_memory, :feature_citation,
                                                    :feature_contact_attributes,
                                                    :welcome_message, :handoff_message, :resolution_message,
                                                    :instructions, :temperature,
                                                    :knowledge_mode, :contextual_chunks,
                                                    # lidas fora da tela e antes ausentes daqui: sem elas o handoff
                                                    # entrega a conversa sem time/fila e a triagem para de reentrar
                                                    :team_id, :triage, :voice_id,
                                                    :fotos_carrossel, :fotos_carrossel_botoes,
                                                    { tools: [] }
                                                  ],
                                                  behavior: {})

    # Handle array parameters separately to allow partial updates
    permitted[:response_guidelines] = params[:assistant][:response_guidelines] if params[:assistant].key?(:response_guidelines)

    permitted[:guardrails] = params[:assistant][:guardrails] if params[:assistant].key?(:guardrails)

    permitted
  end

  def playground_params
    params.require(:assistant).permit(:message_content, message_history: [:role, :content, :agent_name])
  end

  def message_history
    (playground_params[:message_history] || []).map do |message|
      {
        role: message[:role],
        content: message[:content],
        agent_name: message[:agent_name]
      }.compact
    end
  end

  def playground_message_history
    history = message_history
    current_message = playground_params[:message_content]
    return history if current_message.blank?

    current_user_message = { role: 'user', content: current_message }
    return history if history.last == current_user_message

    history + [current_user_message]
  end

  def captain_v2_enabled?
    @assistant.account.feature_enabled?('captain_integration_v2')
  end
end
