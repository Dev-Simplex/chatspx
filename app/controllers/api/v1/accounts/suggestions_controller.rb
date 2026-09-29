# Caixa de sugestoes DENTRO do sistema: qualquer membro da conta manda uma ideia de melhoria para a
# Simplex. Sem policy de admin para ENVIAR de proposito — a ideia boa costuma vir de quem atende.
# Na LISTA, o administrador da conta ve as de todos; os demais (inclusive o supervisor, que no
# banco e administrador com times -- ver AccountUser#console_role), so as proprias.
class Api::V1::Accounts::SuggestionsController < Api::V1::Accounts::BaseController
  LIMITE_MINHAS = 50
  # Conta autora da Simplex (deploy de casa): a unica em que o admin tambem le as sugestoes do link
  # publico, que trazem nome e empresa de gente de fora. Mesma regra do front (helpCenterEmbed.js).
  LINK_READER_HOST = 'https://chat.simplexsolucoes.com.br'.freeze
  LINK_READER_ACCOUNT_ID = 3

  def index
    @all_account = Current.account_user&.console_role == 'administrator'
    @suggestions = visible_suggestions.recentes.limit(LIMITE_MINHAS)
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

  # Admin: as da conta (e, so na conta autora, tambem as do link). Os demais: so as proprias.
  def visible_suggestions
    return Current.account.suggestions.where(user: Current.user) unless @all_account
    return Current.account.suggestions unless link_reader_account?

    Suggestion.where(account: Current.account).or(Suggestion.where(source: :public_link, account_id: nil))
  end

  def link_reader_account?
    Current.account.id == LINK_READER_ACCOUNT_ID && ENV.fetch('FRONTEND_URL', '').chomp('/') == LINK_READER_HOST
  end

  def permitted_params
    params.permit(:content, :media)
  end
end
