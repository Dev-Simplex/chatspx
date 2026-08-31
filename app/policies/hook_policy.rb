class HookPolicy < ApplicationPolicy
  # Conectar/desconectar um app É a tela de Integrações — é aqui que ela escreve
  # (Dyte, OpenAI, Dialogflow, Slack, Notion...). Fora do alcance do supervisor.
  # `process_event?` fica aberto: é o que a sugestão de etiqueta chama de dentro
  # da conversa.
  def create?
    manage?
  end

  def update?
    manage?
  end

  def process_event?
    true
  end

  def destroy?
    manage?
  end

  private

  def manage?
    @account_user.administrator? && !supervisor_settings_blocked?
  end
end
