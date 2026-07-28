class Captain::Behavior::RouterService
  # Padrão SEGURO: sem configuração explícita, a IA não responde dentro de grupo de WhatsApp.
  SKIP_GROUPS_DEFAULT = true

  def initialize(assistant:, conversation:, message:)
    @assistant = assistant
    @conversation = conversation
    @message = message
    @config = assistant.behavior['router'] || {}
  end

  # Só guards TÉCNICOS sobrevivem (D-6): activity, conteúdo vazio, grupos.
  # Guards de NEGÓCIO morreram com o gate por atribuição: whitelist de fones
  # (only_contact_phones), skip_labels, skip_agent_bot (bug latente: lia coluna
  # inexistente) e skip_after_human_response (papel assumido por: gate por
  # atribuição + callback de exclusividade reset_agent_bot_when_assignee_present
  # + A2c, que desatribui o espelho quando um humano responde SEM se atribuir).
  def should_respond?
    return false if @message.activity?
    return false if @message.content.blank? && @message.attachments.blank?
    return false if skip_groups?

    true
  end

  private

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
