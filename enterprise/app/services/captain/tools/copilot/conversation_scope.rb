# Fronteira de conversa dos tools do copilot.
#
# Quem escolhe o `conversation_id` é o MODELO, não o operador: ele digita "resolve essa aí"
# ou "resume o atendimento do Fulano" e o copilot resolve o id sozinho, dentro do laço
# agêntico — não existe passo de aprovação entre decidir e executar (medido: o
# `snooze_conversation`, que é escrita, já rodou sozinho em produção).
#
# Os tools escopavam por `account.conversations`, o que fecha a fronteira de CONTA mas não a
# de ACESSO. Dentro da mesma conta o app tem um segundo limite, e ele é duro: o
# `authorize_team_access` devolve 403 e a UI some com a conversa. Pelo copilot não havia
# limite nenhum — o mesmo usuário que toma 403 na tela lia a conversa inteira (com notas
# privadas) e escrevia nela pelo chat.
#
# A regra NÃO é nova aqui: é a mesma `Conversations::PermissionFilterService` que o
# ConversationFinder, o FilterService, o contacts/conversations_controller e o próprio
# `search_conversation` do copilot já usam. Duas verdades para a mesma regra é como nasce
# divergência silenciosa — então este módulo não decide nada, só chama quem já decide.
module Captain::Tools::Copilot::ConversationScope
  private

  def account
    @assistant.account
  end

  # O conjunto que ESTE usuário pode ver/tocar. Administrador recebe a conta inteira
  # (o service devolve o escopo cru), então nada muda para gestor.
  def permissible_conversations
    Conversations::PermissionFilterService.new(account.conversations, @user, account).perform
  end

  def find_permissible_conversation(display_id)
    permissible_conversations.find_by(display_id: display_id)
  end

  # Recusa FECHADA, no mesmo idioma do resto dos tools (devolve string, não levanta): a
  # chamada é a ação inteira, então recusar é no-op e o texto volta pro modelo, que corrige
  # o alvo ou avisa o operador. Executar assim mesmo gravaria numa conversa que o usuário
  # não pode nem abrir; ignorar em silêncio imprimiria sucesso sobre nada.
  #
  # Distingue "não existe" de "existe e você não alcança" pelo mesmo motivo do #43: recusa
  # sem motivo é indistinguível de alucinação do modelo. Não vaza mais do que a tela já
  # vaza — lá o mesmo caso responde 403, que também revela a existência.
  def conversation_refusal(display_id)
    return 'Conversation not found' unless account.conversations.exists?(display_id: display_id)

    Rails.logger.info(
      "[Copilot] conversa #{display_id} fora do alcance do usuario #{@user&.id} na conta #{account.id}"
    )
    "Conversation ##{display_id} is outside your access scope in this account"
  end
end
