class Captain::Behavior::RouterService
  # Padrão SEGURO: sem configuração explícita, a IA não responde dentro de grupo de WhatsApp.
  SKIP_GROUPS_DEFAULT = true

  def initialize(assistant:, conversation:, message:)
    @assistant = assistant
    @conversation = conversation
    @message = message
    @config = assistant.behavior['router'] || {}
  end

  # Guards TÉCNICOS: activity, conteúdo vazio, grupos — mais o kill-switch por label.
  # Guards de NEGÓCIO morreram com o gate por atribuição: whitelist de fones
  # (only_contact_phones), skip_agent_bot (bug latente: lia coluna inexistente) e
  # skip_after_human_response (papel assumido por: gate por atribuição + callback de
  # exclusividade reset_agent_bot_when_assignee_present + A2c, que desatribui o espelho
  # quando um humano responde SEM se atribuir).
  #
  # `skip_labels` VOLTOU e não é exceção à regra acima: ele não decide por negócio, ele
  # cala a IA quando o interlocutor é outro robô (label `bot-externo`). Esta linha existe
  # porque o comentário que o declarava morto sobreviveu à decisão que o ressuscitou.
  def should_respond?
    return false if @message.activity?
    return false if @message.content.blank? && @message.attachments.blank?
    return false if skip_groups?
    return false if skip_labeled?

    true
  end

  private

  # Kill-switch por conversa (revivido p/ interlocutor-bot): conversa com uma label
  # listada em behavior.router.skip_labels fica MUDA pra IA — determinístico, sem
  # gastar LLM. Uso canônico: label 'bot-externo' quando o outro lado é URA/robô de
  # outra empresa (aplicada por automation rule ou manualmente pelo atendente).
  def skip_labeled?
    skips = Array(@config['skip_labels']).map(&:to_s)
    return false if skips.empty?

    (@conversation.label_list.map(&:to_s) & skips).any?
  end

  # skip_groups continua honrando a config — o que mudou é o DEFAULT.
  #
  # Antes: chave ausente => a IA respondia dentro do grupo. Isso é inseguro por omissão: quem
  # nunca abriu a tela de comportamento tinha a IA falando no meio de um grupo de trabalho, com
  # o classificador lendo mensagens de N pessoas como se fossem de um cliente só.
  # Agora: chave ausente => NÃO responde em grupo. Quem configurou explicitamente (true OU false)
  # continua mandando — inclusive quem quer deliberadamente a IA dentro do grupo (`false`).
  def skip_groups?
    return false unless skip_groups_enabled?

    conversation_is_group?
  end

  # Resolve a config tri-estado: ausente/vazia => SKIP_GROUPS_DEFAULT; presente => valor do usuário
  # (aceita boolean e string, porque a config vem de JSON editado por tela e por API).
  def skip_groups_enabled?
    raw = @config['skip_groups']
    return SKIP_GROUPS_DEFAULT if raw.nil? || raw == ''

    ActiveModel::Type::Boolean.new.cast(raw) || false
  end

  # Delega ao ponto único de verdade (Conversation#group?), que conhece tanto o sinal padrão do
  # Chatwoot (`additional_attributes['type'] == 'group'`) quanto o da WAHA (JID terminando em
  # `@g.us`, no identifier ou nos custom_attributes). A heurística NÃO vive mais aqui.
  def conversation_is_group?
    @conversation.group?
  end
end
