# Login do Captador com o e-mail e a senha do ChatSPX (22 §2.3).
#
# Existe para não usar o /auth/sign_in: aquele limita 5 logins por IP (e o time inteiro sai do IP do
# Captador), cria uma sessão de 2 meses a cada login e devolve o access_token permanente. Aqui nada
# disso: nenhum token é criado, só a identidade e o papel na conta do hook voltam. O 2FA segue o
# mesmo contrato do sign_in: 206 com mfa_token, depois o código (ou backup_code) com o mfa_token.
class Spx::Captador::SessoesController < Spx::Captador::BaseController
  before_action :ensure_login_allowed

  def create
    return verify_mfa if params[:mfa_token].present?
    return render_error(:forbidden, 'saml_required') if User.from_email(email)&.provider == 'saml'

    user = password_user
    return render_error(:unauthorized, 'invalid_credentials') unless user
    return render_error(:forbidden, 'not_account_member') unless account_user(user)
    return render_mfa_required(user) if user.mfa_enabled?

    render_identity(user)
  end

  private

  def ensure_login_allowed
    render_error(:forbidden, 'login_not_allowed') unless ActiveModel::Type::Boolean.new.cast(@hook.settings['allow_login'])
  end

  def email
    params[:email].to_s.strip.downcase
  end

  # As checagens de DeviseOverrides::SessionsController#find_user_for_authentication, que é privado.
  def password_user
    return if email.blank? || params[:password].blank?

    user = User.from_email(email)
    user if user&.valid_password?(params[:password]) && user.active_for_authentication?
  end

  def render_mfa_required(user)
    render json: { mfa_required: true, mfa_token: Mfa::TokenService.new(user: user).generate_token }, status: :partial_content
  end

  def verify_mfa
    user = Mfa::TokenService.new(token: params[:mfa_token]).verify_token
    return render_error(:unauthorized, 'mfa_token_invalid') unless user

    code_ok = Mfa::AuthenticationService.new(user: user, otp_code: params[:otp_code], backup_code: params[:backup_code]).authenticate
    return render_error(:unauthorized, 'invalid_credentials') unless code_ok && user.active_for_authentication?
    return render_error(:forbidden, 'not_account_member') unless account_user(user)

    render_identity(user)
  end

  def account_user(user)
    @account_user ||= @account.account_users.find_by(user_id: user.id)
  end

  def render_identity(user)
    render json: {
      user: { id: user.id, name: user.name, available_name: user.available_name, email: user.email, avatar_url: user.avatar_url },
      account: { id: @account.id, name: @account.name, role: account_user(user).role, permissions: account_user(user).permissions },
      teams: user.teams.where(account_id: @account.id).map { |team| { id: team.id, name: team.name } }
    }
  end
end
