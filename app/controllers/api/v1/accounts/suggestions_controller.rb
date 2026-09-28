# Caixa de sugestoes DENTRO do sistema: qualquer membro da conta manda uma ideia de melhoria para a
# Simplex e ve as proprias no "Minhas sugestoes". Sem policy de admin de proposito — a ideia boa
# costuma vir de quem atende, nao de quem administra.
class Api::V1::Accounts::SuggestionsController < Api::V1::Accounts::BaseController
  LIMITE_MINHAS = 50

  def index
    @suggestions = Current.account.suggestions.where(user: Current.user).recentes.limit(LIMITE_MINHAS)
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
