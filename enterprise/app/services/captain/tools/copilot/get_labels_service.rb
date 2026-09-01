class Captain::Tools::Copilot::GetLabelsService < Captain::Tools::BaseTool
  def self.name
    'get_labels'
  end
  description 'List all available labels in the account'

  # Esta é a lista de onde o modelo tira o texto que passa pro `add_label` — enumerar e
  # aplicar são o mesmo par. Ela ignorava `Label.visibility`, que é feature deste fork:
  # devolvia label `personal` de outro usuário e label `team` de time do qual o operador
  # não participa, exatamente o que a tela esconde. `Label.with_visibility` é a mesma
  # regra que o labels_controller#index usa — nenhuma cópia nova.
  def execute
    labels = Label.with_visibility(@user, @assistant.account).pluck(:title)
    return 'No labels found in this account' if labels.empty?

    "Available labels: #{labels.join(', ')}"
  end

  # Único tool do copilot sem `active?`: era registrado até quando não há usuário na sessão
  # (o gatilho `#copilot` monta o ChatService sem user_id), e aí não há de quem respeitar a
  # visibilidade. Listar catálogo não pede permissão específica — a política do próprio
  # recurso diz "qualquer membro logado lista" —, pede que exista alguém.
  def active?
    @user.present?
  end
end
