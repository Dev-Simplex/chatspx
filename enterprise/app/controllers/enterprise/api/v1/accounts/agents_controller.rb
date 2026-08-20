module Enterprise::Api::V1::Accounts::AgentsController
  def create
    super
    return if @agent.blank?

    associate_agent_with_custom_role
  end

  def update
    super
    associate_agent_with_custom_role
  end

  private

  # T1: este método roda depois do `super` e escreve custom_role_id INCONDICIONALMENTE —
  # sem a guarda, o supervisor de time renomeando alguém (request sem a chave) ZERARIA a
  # função personalizada do alvo, que é justamente uma troca de função que ele não pode
  # fazer. Admin segue com o comportamento de sempre.
  def associate_agent_with_custom_role
    return unless Current.account_user&.administrator?

    @agent.current_account_user.update!(custom_role_id: params[:custom_role_id])
  end
end
