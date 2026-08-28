class Api::V1::AccountsController < Api::BaseController
  include AuthHelper
  include CacheKeysHelper

  CAPTAIN_LEGADO = SuperAdmin::AccountFeaturesHelper::LEGACY_CAPTAIN_FEATURE
  CAPTAIN_CANONICO = SuperAdmin::AccountFeaturesHelper::CANONICAL_CAPTAIN_FEATURE

  skip_before_action :authenticate_user!, :set_current_user, :handle_with_exception,
                     only: [:create], raise: false
  before_action :check_signup_enabled, only: [:create]
  before_action :ensure_account_name, only: [:create]
  before_action :validate_captcha, only: [:create]
  before_action :fetch_account, except: [:create]
  before_action :check_authorization, except: [:create]
  before_action :check_conversation_workflow_authorization, only: [:update]

  # Os ajustes que a tela "Fluxo de conversa" grava. Ela não tem controller próprio —
  # escreve em account.settings pelo mesmo PATCH /accounts/:id que "Configurações da
  # conta" usa. Por isso a negação ao supervisor de time é por CHAVE: ele segue editando
  # nome/idioma/domínio da conta, e só estas cinco saem do alcance dele.
  CONVERSATION_WORKFLOW_SETTINGS = %w[
    auto_resolve_after auto_resolve_message auto_resolve_ignore_waiting auto_resolve_label
    conversation_required_attributes
  ].freeze

  rescue_from CustomExceptions::Account::InvalidEmail,
              CustomExceptions::Account::InvalidParams,
              CustomExceptions::Account::UserExists,
              CustomExceptions::Account::UserErrors,
              with: :render_error_response

  def show
    @latest_chatwoot_version = ::Redis::Alfred.get(::Redis::Alfred::LATEST_CHATWOOT_VERSION)
    @maintenance_banner = begin
      MaintenanceBanner.info
    rescue StandardError => e
      Rails.logger.error("Error fetching maintenance banner: #{e.message}")
      { enabled: false }
    end
    @update_banner = begin
      UpdateBanner.info
    rescue StandardError => e
      Rails.logger.error("Error fetching update banner: #{e.message}")
      { enabled: false }
    end
    render 'api/v1/accounts/show', format: :json
  end

  def create
    @user, @account = AccountBuilder.new(
      account_name: account_params[:account_name],
      user_full_name: account_params[:user_full_name],
      email: account_params[:email],
      user_password: account_params[:password],
      locale: account_params[:locale],
      user: current_user
    ).perform
    if @user
      send_auth_headers(@user)
      render 'api/v1/accounts/create', format: :json, locals: { resource: @user }
    else
      render_error_response(CustomExceptions::Account::SignupFailed.new({}))
    end
  end

  def cache_keys
    expires_in 10.seconds, public: false, stale_while_revalidate: 5.minutes
    render json: { cache_keys: cache_keys_for_account }, status: :ok
  end

  def update
    @account.assign_attributes(account_params.slice(:name, :locale, :domain, :support_email))
    @account.custom_attributes.merge!(custom_attributes_params)
    @account.settings.merge!(settings_params)
    @account.custom_attributes['onboarding_step'] = 'invite_team' if @account.custom_attributes['onboarding_step'] == 'account_update'
    @account.save!
  end

  # Ligar e desligar feature PELA TELA. Antes disto so havia o console, o super_admin (Administrate)
  # ou a Platform API, que exige token de PlatformApp — nenhum ao alcance do admin da conta.
  #
  # GET devolve o catalogo inteiro com o estado de cada uma, e nao so as ligadas: a tela precisa
  # mostrar o que existe para poder oferecer. O `_account.json.jbuilder` continua expondo so as
  # ligadas, entao nada muda para o resto do front.
  #
  # PATCH e MERGE, nao replace: recebe `{ features: { nome => true|false } }` e mexe SO no que veio.
  # Deliberado — `selected_feature_flags=` (FlagShihTzu) zera todos os bits antes de ligar os
  # enviados, entao uma requisicao parcial apagaria o resto. E o mesmo estrago do "salvar apagava o
  # config do agente" que ja foi corrigido neste fork.
  def features
    return render json: catalogo if request.get?

    pedidos = params.fetch(:features, {}).to_unsafe_h

    desconhecidas = AccountFeaturesCatalog.desconhecidas(pedidos.keys)
    return render json: { error: "feature desconhecida: #{desconhecidas.join(', ')}" }, status: :unprocessable_entity if desconhecidas.any?

    bloqueadas = AccountFeaturesCatalog.bloqueadas(pedidos)
    if bloqueadas.any?
      return render json: { error: I18n.t('errors.features.sem_bit', features: bloqueadas.join(', ')) },
                    status: :unprocessable_entity
    end

    aplicar_features(pedidos)
    render json: catalogo
  end

  def update_active_at
    @current_account_user.active_at = Time.now.utc
    @current_account_user.save!
    head :ok
  end

  CHAT_WALLPAPER_TYPES = %w[image/jpeg image/png image/webp].freeze
  CHAT_WALLPAPER_MAX_BYTES = 5.megabytes

  def chat_wallpaper
    return remove_chat_wallpaper if request.delete?

    file = params[:image]
    error = chat_wallpaper_validation_error(file)
    return render(json: { error: error }, status: :unprocessable_entity) if error

    @account.chat_wallpaper_image.attach(file)
    url = Rails.application.routes.url_helpers.rails_blob_url(@account.chat_wallpaper_image, only_path: true)
    @account.settings['chat_wallpaper_url'] = url
    @account.save!
    render json: { url: url }
  end

  private

  # `enable_features!`/`disable_features!` usam `save` e nao `save!`, entao gravam calado quando uma
  # validacao reprova. Aqui se usa `save!` uma vez so, depois de montar tudo: a requisicao falha alto
  # em vez de responder 200 sem ter gravado.
  def catalogo
    AccountFeaturesCatalog.new(@account).to_h
  end

  def aplicar_features(pedidos)
    ligar, desligar = pedidos.partition { |_nome, valor| AccountFeaturesCatalog.ligar?(valor) }.map { |par| par.map(&:first) }

    # O Captain v1 e legado e anda junto do v2 — mesma regra que o super_admin ja aplica
    # (SuperAdmin::AccountsController#synchronized_captain_feature_flags). Sem isto, ligar o v2 pela
    # tela deixaria os dois em estados diferentes.
    ligar << CAPTAIN_LEGADO if ligar.include?(CAPTAIN_CANONICO) && @account.feature_enabled?(CAPTAIN_LEGADO)
    desligar << CAPTAIN_LEGADO if desligar.include?(CAPTAIN_CANONICO)

    @account.enable_features(*ligar.uniq)
    @account.disable_features(*(desligar.uniq - ligar))
    @account.save!
  end

  def remove_chat_wallpaper
    @account.chat_wallpaper_image.purge if @account.chat_wallpaper_image.attached?
    @account.settings['chat_wallpaper_url'] = ''
    @account.save!
    render json: { url: '' }
  end

  def chat_wallpaper_validation_error(file)
    return 'no_file' if file.blank?
    return 'invalid_type' unless CHAT_WALLPAPER_TYPES.include?(file.content_type)
    return 'too_large' if file.size > CHAT_WALLPAPER_MAX_BYTES

    nil
  end

  def ensure_account_name
    # ensure that account_name and user_full_name is present
    # this is becuase the account builder and the models validations are not triggered
    # this change is to align the behaviour with the v2 accounts controller
    # since these values are not required directly there
    return if account_params[:account_name].present?
    return if account_params[:user_full_name].present?

    raise CustomExceptions::Account::InvalidParams.new({})
  end

  def cache_keys_for_account
    {
      label: fetch_value_for_key(params[:id], Label.name.underscore),
      inbox: fetch_value_for_key(params[:id], Inbox.name.underscore),
      team: fetch_value_for_key(params[:id], Team.name.underscore)
    }
  end

  def fetch_account
    @account = current_user.accounts.find(params[:id])
    @current_account_user = @account.account_users.find_by(user_id: current_user.id)
  end

  def check_conversation_workflow_authorization
    return unless SupervisorSettingsScope.blocked?(current_user, @account)
    raise Pundit::NotAuthorizedError if params.keys.intersect?(CONVERSATION_WORKFLOW_SETTINGS)
  end

  def account_params
    params.permit(:account_name, :email, :name, :password, :locale, :domain, :support_email, :user_full_name)
  end

  def custom_attributes_params
    params.permit(:industry, :company_size, :timezone)
  end

  def settings_params
    params.permit(*permitted_settings_attributes)
  end

  def permitted_settings_attributes
    [:auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting, :audio_transcriptions, :auto_resolve_label,
     :chat_wallpaper_url, :show_dashboard_kpi_strip, :onboarding_dismissed, :resolve_assignment_gate,
     :openai_api_key, :openai_model_default, :openai_model_advanced,
     :reply_assignment_gate, :ia_reentra_orfa, :orphan_retriage_after, :queue_escalation_after, :takeover_request_gate,
     { onboarding_completed_steps: [] }]
  end

  def check_signup_enabled
    raise ActionController::RoutingError, 'Not Found' unless GlobalConfigService.account_signup_enabled?
  end

  def validate_captcha
    raise ActionController::InvalidAuthenticityToken, 'Invalid Captcha' unless ChatwootCaptcha.new(params[:h_captcha_client_response]).valid?
  end

  def pundit_user
    {
      user: current_user,
      account: @account,
      account_user: @current_account_user
    }
  end
end

Api::V1::AccountsController.prepend_mod_with('Api::V1::AccountsSettings')
