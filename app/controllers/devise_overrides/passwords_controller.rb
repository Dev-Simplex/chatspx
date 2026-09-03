class DeviseOverrides::PasswordsController < Devise::PasswordsController
  include AuthHelper

  skip_before_action :require_no_authentication, raise: false
  skip_before_action :authenticate_user!, raise: false

  def create
    @user = User.from_email(params[:email])
    @user&.send_reset_password_instructions
    build_response(I18n.t('messages.reset_password'), 200)
  end

  def update
    # params: reset_password_token, password, password_confirmation
    original_token = params[:reset_password_token]
    reset_password_token = Devise.token_generator.digest(self, :reset_password_token, original_token)
    @recoverable = User.find_by(reset_password_token: reset_password_token)
    if @recoverable && reset_password_and_confirmation(@recoverable)
      send_auth_headers(@recoverable)
      render partial: 'devise/auth', formats: [:json], locals: { resource: @recoverable }
    else
      render json: link_invalido, status: :unprocessable_entity
    end
  end

  private

  # A pessoa aqui NAO errou nada: o link dela e velho. So existe UM token por usuario, entao cada novo
  # pedido de recuperacao sobrescreve o anterior e mata os e-mails ja enviados.
  #
  # Isto virou correcao porque a mensagem antiga era o literal 'Invalid token', em ingles e sem dizer
  # o que fazer. Em 31/08/2026 uma usuaria da Catatau pediu recuperacao 5 vezes e tentou 4 links
  # diferentes, sempre um antigo: como o erro nao explicava que o problema era a IDADE do link, cada
  # tentativa frustrada virava um pedido novo, que por sua vez matava o e-mail recem-chegado.
  #
  # O `code` vai junto para o front poder traduzir no idioma de QUEM ESTA VENDO. O servidor nao sabe
  # o idioma de um visitante deslogado; o navegador sabe.
  def link_invalido
    {
      message: I18n.t('messages.reset_password_link_invalid'),
      code: 'reset_token_invalid',
      redirect_url: '/'
    }
  end

  def reset_password_and_confirmation(recoverable)
    recoverable.confirm unless recoverable.confirmed? # confirm if user resets password without confirming anytime before
    recoverable.reset_password(params[:password], params[:password_confirmation])
    recoverable.reset_password_token = nil
    recoverable.confirmation_token = nil
    recoverable.reset_password_sent_at = nil
    recoverable.save!
  end

  def build_response(message, status)
    render json: {
      message: message
    }, status: status
  end
end

DeviseOverrides::PasswordsController.prepend_mod_with('DeviseOverrides::PasswordsController')
