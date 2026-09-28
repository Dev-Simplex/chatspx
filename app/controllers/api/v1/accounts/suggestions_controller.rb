# Caixa de sugestoes DENTRO do sistema: qualquer membro da conta manda uma ideia de melhoria para a
# Simplex. Sem policy de admin para ENVIAR de proposito — a ideia boa costuma vir de quem atende.
# Na LISTA, o administrador da conta ve as de todos; os demais (inclusive o supervisor, que no
# banco e administrador com times -- ver AccountUser#console_role), so as proprias.
class Api::V1::Accounts::SuggestionsController < Api::V1::Accounts::BaseController
  LIMITE_MINHAS = 50

  def index
    @all_account = Current.account_user&.console_role == 'administrator'
    scope = Current.account.suggestions
    scope = scope.where(user: Current.user) unless @all_account
    @suggestions = scope.recentes.limit(LIMITE_MINHAS)
  end

  def create
    @suggestion = Current.account.suggestions.new(
      user: Current.user,
      name: Current.user.name,
      company: Current.account.name,
      source: :in_app,
      content: permitted_params[:content]
    )
    @suggestion.media.attach(permitted_params[:media]) if permitted_params[:media].present?

    return render json: { error: @suggestion.errors.full_messages.to_sentence }, status: :unprocessable_entity unless @suggestion.save

    render 'api/v1/accounts/suggestions/show'
  end

  private

  def permitted_params
    params.permit(:content, :media)
  end
end
