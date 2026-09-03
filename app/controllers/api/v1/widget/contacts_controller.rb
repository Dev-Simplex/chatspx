class Api::V1::Widget::ContactsController < Api::V1::Widget::BaseController
  include WidgetHelper

  # Campos que ligam esta sessao de widget a uma identidade. Qualquer um deles faz
  # o ContactIdentifyAction procurar um contato existente e, quando acha, MESCLAR o
  # contato da sessao dentro dele (contact_identify_action.rb:36-47,72-85) — o que
  # move o contact_inbox da sessao para o contato encontrado e entrega ao chamador
  # o historico de conversas dele. Por isso, em inbox com HMAC obrigatorio, uma
  # chamada que carregue qualquer um destes precisa vir assinada.
  IDENTITY_BINDING_PARAMS = [:identifier, :email, :phone_number].freeze

  before_action :validate_hmac, only: [:set_user]
  before_action :validate_hmac_for_identified_update, only: [:update]

  def show; end

  def update
    identify_contact(@contact)
  end

  def set_user
    contact = nil

    if a_different_contact?
      @contact_inbox, @widget_auth_token = build_contact_inbox_with_token(@web_widget)
      contact = @contact_inbox.contact
    else
      contact = @contact
    end

    # Bloco 4.15: `should_verify_hmac?` deixou de implicar "assinatura conferida". Sob
    # `observado` a requisicao chega ate aqui SEM assinatura valida — de proposito, para
    # nao quebrar sessao — e marcar a sessao como verificada apagaria exatamente o sinal
    # de que o relatorio de enforcement depende. Para `desativado` e `obrigatorio` isto e
    # equivalente ao que ja acontecia: nos dois, chegar aqui ja significava assinatura ok.
    @contact_inbox.update(hmac_verified: true) if should_verify_hmac? && valid_hmac?

    identify_contact(contact)
  end

  # TODO : clean up this with proper routes delete contacts/custom_attributes
  def destroy_custom_attributes
    @contact.custom_attributes = @contact.custom_attributes.excluding(params[:custom_attributes])
    @contact.save!
    render json: @contact
  end

  private

  def identify_contact(contact)
    contact_identify_action = ContactIdentifyAction.new(
      contact: contact,
      params: identified_params.to_h.deep_symbolize_keys,
      discard_invalid_attrs: true,
      # Bloco 4.17: quem escreve daqui e o site. Atributo protegido so passa em sessao
      # com assinatura conferida.
      verified_origin: @contact_inbox&.hmac_verified?
    )
    @contact = contact_identify_action.perform
  end

  def a_different_contact?
    @contact.identifier.present? && @contact.identifier != identified_params[:identifier]
  end

  # O update tambem serve ao prechat anonimo e ao setCustomAttributes
  # (name/custom_attributes sem identifier), que precisam continuar funcionando
  # ate em inbox com HMAC obrigatorio — nenhum dos dois consegue reamarrar a
  # sessao a outro contato. Ja o caminho de identidade exige HMAC.
  def validate_hmac_for_identified_update
    return if params[:identifier].blank? && !identity_binding_request?

    validate_hmac
  end

  # PORTA 1 (B5): so o identifier era tratado como identidade. email e
  # phone_number amarram a sessao do mesmo jeito, via merge, e passavam sem
  # assinatura mesmo com o modo obrigatorio ligado.
  #
  # Bloco 4.15: `observado` entra aqui junto com `obrigatorio` de proposito. Os dois
  # precisam reconhecer o MESMO universo de requisicoes — se `observado` medisse um
  # universo menor, o numero dele nao serviria para decidir a virada para estrito.
  def identity_binding_request?
    return false unless widget_inbox.identity_enforcement_watching?

    # Bloco 5.19: o token e campo de identidade como os outros tres — ele amarra a sessao a um
    # `sub`. Fora daqui ele nao teria como ser conferido no `update`.
    return true if params[:identity_token].present?

    IDENTITY_BINDING_PARAMS.any? { |field| params[field].present? }
  end

  def validate_hmac
    return unless should_verify_hmac?
    return if valid_hmac?

    # Bloco 4.15: sob `observado` a requisicao SEGUE. Nenhuma sessao quebra — e por
    # isso que ligar o estado do meio numa inbox com trafego e seguro. O que ela
    # deixa atras de si e contabilidade, e a contabilidade e derivada de
    # `contact_inboxes.hmac_verified` (Identity::EnforcementReport), nao deste log.
    return observe_unverified_identity if widget_inbox.identity_enforcement_observed?

    render json: { error: 'HMAC failed: Invalid Identifier Hash Provided' }, status: :unauthorized
  end

  def observe_unverified_identity
    campos = IDENTITY_BINDING_PARAMS.select { |field| params[field].present? }.join(',')
    Rails.logger.info(
      "[identity_enforcement] observado inbox_id=#{widget_inbox.id} " \
      "contact_inbox_id=#{@contact_inbox&.id} campos=#{campos}"
    )
    nil
  end

  # `set_web_widget` garante `@web_widget`; o `inbox` do BaseController depende do
  # auth token, que nao esta garantido em todo caminho deste controller.
  def widget_inbox
    @widget_inbox ||= @web_widget.inbox
  end

  def should_verify_hmac?
    # Modos `obrigatorio` e `observado`: quem chegou ate aqui carrega campo de
    # identidade, entao a checagem nao pode ser desligada por nada.
    return true if widget_inbox.identity_enforcement_watching?

    # Bloco 5.19: o que pede verificacao e o token que PROVA, nao o token que apareceu. A diferenca
    # e o aceite do bloco: se a presenca bastasse, um token expirado numa inbox `desativado` viraria
    # 401 — e o contrato diz que ele degrada para anonimo, nao para erro. Como so entra aqui o token
    # ja verificado, esta linha nunca cria uma recusa nova: ela so faz a sessao ser MARCADA como
    # verificada quando ha prova.
    return true if identity_token_result.verified?

    return false if params[:identifier_hash].blank?

    # PORTA 2 (B5): daqui saiu um early return que devolvia false quando
    # custom_attributes vinha presente e identifier vinha em branco. Era um
    # interruptor de desligar a verificacao controlado pelo proprio chamador.
    true
  end

  # Bloco 5.19: duas provas possiveis, UMA porta de decisao. O JWT e formato adicional — quem
  # decide o que fazer com a ausencia de prova continua sendo a maquina de estados do 4.15, e nao
  # existe caminho paralelo por onde um token entre sem passar por aqui.
  def valid_hmac?
    valid_identifier_hash? || identity_token_result.verified?
  end

  # Bloco 5.19: o token de identidade emitido pelo SERVIDOR DO CLIENTE, assinado com o mesmo
  # segredo do HMAC. O visitante nao assina nada — so carrega o que recebeu pronto.
  def identity_token_result
    @identity_token_result ||= Widget::IdentityTokenService.new(
      token: params[:identity_token],
      hmac_token: @web_widget.hmac_token
    ).perform
  end

  def valid_identifier_hash?
    # Nao se prova uma identidade que nao foi declarada: sem identifier nao existe
    # hash valido possivel, e assinar a string vazia nao pode valer como prova.
    return false if params[:identifier].blank? || params[:identifier_hash].blank?

    expected_hash = OpenSSL::HMAC.hexdigest(
      'sha256',
      @web_widget.hmac_token,
      params[:identifier].to_s
    )
    identifier_hash = params[:identifier_hash].to_s
    return false unless identifier_hash.bytesize == expected_hash.bytesize

    ActiveSupport::SecurityUtils.secure_compare(identifier_hash, expected_hash)
  end

  def permitted_params
    params.permit(:website_token, :identifier, :identifier_hash, :email, :name, :avatar_url, :phone_number, custom_attributes: {},
                                                                                                            additional_attributes: {})
  end

  # Bloco 5.19: o que o token ASSINADO prova vence o que o corpo apenas afirma. O corpo chega do
  # navegador do visitante e nao e prova de nada; o payload do token foi assinado pelo servidor do
  # cliente. Token nao verificado nao contribui com campo nenhum — e assim que "expirado degrada
  # para anonimo" acontece: os campos dele simplesmente nao existem para o resto do fluxo.
  #
  # Separado de `permitted_params` de proposito: `set_web_widget` (WebsiteTokenHelper) chama
  # `permitted_params` para ACHAR o canal, entao ele nao pode depender do canal para existir.
  def identified_params
    result = identity_token_result
    return permitted_params unless result.verified?

    permitted_params.merge(result.attributes).merge('identifier' => result.identifier)
  end
end
