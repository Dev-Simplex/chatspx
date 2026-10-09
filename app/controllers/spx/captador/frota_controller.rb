# Frota (docs/contratos/captador.md, seção "Frota"): o Captador lista as contas desta instalação e
# liga a integração numa delas, sem ninguém passar pelo Super Admin e por Integrações.
#
# Máquina a máquina, com um token por instalação em CAPTADOR_FROTA_TOKEN (Bearer). Sem a variável, ou
# com menos de 32 caracteres, as rotas respondem 404, como se não existissem. Token errado: 401 sem
# corpo. Nada aqui devolve o shared_secret nem token algum.
class Spx::Captador::FrotaController < ActionController::API
  APP_ID = 'captador'.freeze
  TOKEN_MINIMO = 32
  CAMPOS = %w[captador_url instance_key shared_secret allowed_inbox_ids allow_login].freeze
  CANAIS_LIBERAVEIS = %w[Channel::Whatsapp Channel::Api].freeze

  before_action :autenticar_frota!

  # ponytail: algumas consultas por conta; a instalação tem dezenas de contas, não milhares.
  def index
    render json: { servidor: servidor, contas: Account.order(:id).map { |account| conta_json(account) } }
  end

  def ativar
    account = Account.find_by(id: params[:id])
    return head :not_found unless account

    settings, erro = settings_pedidas(account)
    return render_invalido([erro]) if erro

    ativar_integracao(account, settings)
    render json: conta_json(account.reload)
  rescue ActiveRecord::RecordInvalid => e
    render_invalido(e.record.errors.full_messages)
  end

  private

  # Compara os SHA-256 para o tempo não depender nem do conteúdo nem do tamanho do token recebido.
  def autenticar_frota!
    esperado = ENV.fetch('CAPTADOR_FROTA_TOKEN', '')
    return head :not_found if esperado.length < TOKEN_MINIMO

    recebido = request.authorization.to_s[/\ABearer (.+)\z/, 1].to_s
    valido = ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(recebido), Digest::SHA256.hexdigest(esperado))
    head :unauthorized unless valido
  end

  def servidor
    URI.parse(ENV.fetch('FRONTEND_URL', '')).host
  rescue URI::InvalidURIError
    nil
  end

  # O mesmo que o Super Admin (chave da conta) e Integrações → Captador (hook) fazem, numa transação
  # só, com a auditoria dentro: se ela falhar, nada fica gravado. O lock da conta serializa duas
  # ativações simultâneas, que de outro modo criariam dois hooks.
  def ativar_integracao(account, settings)
    account.with_lock do
      account.update!(captador_integration_enabled: true)
      hook = account.hooks.find_or_initialize_by(app_id: APP_ID)
      hook.update!(status: 'enabled', settings: hook.settings.to_h.merge(settings))
      registrar(account, hook)
    end
  end

  # Só os campos do schema do apps.yml; o modelo valida tipos e formatos e cifra o segredo. O segredo
  # vazio numa conta que já tem hook mantém o atual, como na tela de Integrações.
  def settings_pedidas(account)
    pedidas = params.to_unsafe_h.slice(*CAMPOS)
    if pedidas['shared_secret'].to_s.start_with?(Integrations::Hook::CAPTADOR_SECRET_PREFIX)
      return [nil, 'shared_secret não pode começar com o prefixo de valor cifrado']
    end
    return [pedidas, nil] unless pedidas.key?('allowed_inbox_ids')

    caixas = caixas_liberadas(account, pedidas['allowed_inbox_ids'])
    return [nil, 'allowed_inbox_ids deve ser uma lista de ids de caixa ou "todas"'] unless caixas

    [pedidas.merge('allowed_inbox_ids' => caixas), nil]
  end

  # "todas" vira as caixas que o Captador pode usar (WhatsApp oficial e API/WAHA), as únicas que o hook aceita.
  def caixas_liberadas(account, valor)
    return account.inboxes.where(channel_type: CANAIS_LIBERAVEIS).order(:id).pluck(:id).join(',') if valor == 'todas'

    valor.join(',') if valor.is_a?(Array) && valor.all? { |id| id.is_a?(Integer) && id.positive? }
  end

  def render_invalido(erros)
    render json: { error_code: 'configuracao_invalida', meta: { erros: erros } }, status: :unprocessable_entity
  end

  # Quem chama é o Captador, com o token da frota: ficam o IP e o User-Agent. Vai para a auditoria do
  # Enterprise (a tabela que o Super Admin já alimenta) e para o log, só com o que o GET também mostra.
  def registrar(account, hook)
    estado = hook_json(hook)
    Audited.audit_class.create!(
      auditable_type: 'Integrations::Hook', auditable_id: hook.id, associated_type: 'Account', associated_id: account.id,
      action: 'update', comment: 'captador.frota.ativar', remote_address: request.remote_ip,
      audited_changes: { 'captador_integration' => true, 'hook' => estado }
    )
    Rails.logger.info(
      "[Captador][frota] ativar conta=#{account.id} hook=#{hook.id} caixas=#{estado[:allowed_inbox_ids].join(',')} " \
      "allow_login=#{estado[:allow_login]} ip=#{request.remote_ip} agente=#{request.user_agent.to_s.truncate(80).inspect}"
    )
  end

  def conta_json(account)
    {
      id: account.id,
      nome: account.name,
      status: account.status,
      criada_em: account.created_at.utc.iso8601,
      usuarios: account.account_users.count,
      caixas: account.inboxes.order(:id).map { |inbox| { id: inbox.id, nome: inbox.name, canal: inbox.channel_type } },
      admins: account.administrators.order(:id).map { |user| { nome: user.name, email: user.email } },
      captador: {
        integracao_habilitada: account.captador_integration_enabled?,
        hook: hook_json(account.hooks.find_by(app_id: APP_ID))
      }
    }
  end

  def hook_json(hook)
    return if hook.nil?

    settings = hook.settings.to_h
    {
      id: hook.id,
      status: hook.status,
      captador_url: settings['captador_url'],
      instance_key: settings['instance_key'],
      allowed_inbox_ids: settings['allowed_inbox_ids'].to_s.split(',').map(&:to_i),
      allow_login: ActiveModel::Type::Boolean.new.cast(settings['allow_login']) || false
    }
  end
end
