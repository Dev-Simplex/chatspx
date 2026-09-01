# retain_original_contact_name: false / true
# In case of setUser we want to update the name of the identified contact,
# which is the default behaviour
#
# But, In case of contact merge during prechat form contact update.
# We don't want to update the name of the identified original contact.

class ContactIdentifyAction
  include UrlHelper
  # `identity_enforcement` (bloco 4.16) e o estado RESOLVIDO da inbox que originou a
  # chamada — `nil` para quem chama de fora do widget, e nil se comporta como hoje.
  # `verified_origin` (bloco 4.17) diz se a sessao que originou a chamada teve a identidade
  # conferida por assinatura.
  #
  # O default e `false`, e a mudanca de `true` para `false` E o conserto do bloco. Com o
  # default aberto, quem esquecesse o argumento herdava "origem verificada" sem apresentar
  # credencial nenhuma — foi assim que `Public::Api::V1::Inboxes::ContactsController#update`
  # nasceu furado: ele nao passava nada, e por isso sobrescrevia atributo protegido com 200.
  # Um default que erra para o lado de negar produz uma escrita recusada com log; um default
  # que erra para o lado de permitir produz um portao aberto que ninguem ve. Todo chamador
  # real declara o seu valor explicitamente, entao este default nao decide nada hoje — ele
  # existe para o chamador de amanha.
  pattr_initialize [:contact!, :params!, { retain_original_contact_name: false, discard_invalid_attrs: false,
                                           identity_enforcement: nil, verified_origin: false }]

  def perform
    @attributes_to_update = [:identifier, :name, :email, :phone_number]

    ActiveRecord::Base.transaction do
      merge_if_existing_identified_contact
      merge_if_existing_email_contact
      merge_if_existing_phone_number_contact
      update_contact
    end
    @contact
  end

  private

  def account
    @account ||= @contact.account
  end

  def merge_if_existing_identified_contact
    return unless merge_contacts?(existing_identified_contact, :identifier)

    process_contact_merge(existing_identified_contact)
  end

  def merge_if_existing_email_contact
    return unless merge_contacts?(existing_email_contact, :email)
    return if refuse_merge_under_enforcement?(:email, existing_email_contact)

    process_contact_merge(existing_email_contact)
  end

  def merge_if_existing_phone_number_contact
    return unless merge_contacts?(existing_phone_number_contact, :phone_number)
    return if refuse_merge_under_enforcement?(:phone_number, existing_phone_number_contact)
    return unless mergable_phone_contact?

    process_contact_merge(existing_phone_number_contact)
  end

  # PORTAS 3 e 4 (bloco 4.16). O pre-chat (widget/conversations#create) e o input_email
  # (widget/messages#update) chamam esta action sem identifier e sem assinatura, e nao
  # existe como o visitante assinar: o segredo do HMAC e do servidor do cliente. Por isso a
  # recusa sob enforcement estrito NAO pode ser da requisicao — recusar a requisicao
  # desligaria a coleta de e-mail do pre-chat inteira, para todo mundo, inclusive para o
  # visitante novo que nao tem nada a ver com o problema.
  #
  # A recusa e do MERGE, que e onde mora o dano: absorver um cadastro existente move o
  # contact_inbox da sessao para ele e entrega a quem digitou o e-mail o historico de
  # conversas do dono do e-mail.
  #
  # E so quando o campo pertence a OUTRO cadastro. Visitante novo digitando o proprio
  # e-mail nao gera merge nenhum, entao nada muda para ele.
  def refuse_merge_under_enforcement?(key, existing_contact)
    return false unless strict_identity?

    # Nao se funde e nao se reivindica o campo: reivindicar bateria no indice unico
    # por conta (`uniq_email_per_account_contact`) e derrubaria a criacao da conversa.
    @attributes_to_update.delete(key)
    Rails.logger.info(
      "[identity_enforcement] merge recusado key=#{key} account_id=#{account.id} " \
      "sessao=#{@contact.id} dono=#{existing_contact.id}"
    )
    true
  end

  def strict_identity?
    identity_enforcement.to_s == IdentityEnforceable::STRICT
  end

  def process_contact_merge(mergee_contact)
    @contact = merge_contact(mergee_contact, @contact)
    @attributes_to_update.delete(:name) if retain_original_contact_name
  end

  def existing_identified_contact
    return if params[:identifier].blank?

    @existing_identified_contact ||= account.contacts.find_by(identifier: params[:identifier])
  end

  def existing_email_contact
    return if params[:email].blank?

    @existing_email_contact ||= account.contacts.from_email(params[:email])
  end

  def existing_phone_number_contact
    return if params[:phone_number].blank?

    @existing_phone_number_contact ||= account.contacts.find_by(phone_number: params[:phone_number])
  end

  def merge_contacts?(existing_contact, key)
    return if existing_contact.blank?

    return true if params[:identifier].blank?

    # we want to prevent merging contacts with different identifiers
    if existing_contact.identifier.present? && existing_contact.identifier != params[:identifier]
      # we will remove attribute from update list
      @attributes_to_update.delete(key)
      return false
    end

    true
  end

  # case: contact 1: email: 1@test.com, phone: 123456789
  # params: email: 2@test.com, phone: 123456789
  # we don't want to overwrite 1@test.com since email parameter takes higer priority
  def mergable_phone_contact?
    return true if params[:email].blank?

    if existing_phone_number_contact.email.present? && existing_phone_number_contact.email != params[:email]
      @attributes_to_update.delete(:phone_number)
      return false
    end
    true
  end

  # Bloco 5.17 — os UNICOS campos que o verbo `set…` pode apagar, e o valor com que cada um fica
  # vazio. Lista FECHADA, e o que esta FORA dela e tao deliberado quanto o que esta dentro:
  #
  # · `identifier` — apagar o identificador desamarraria o contato da identidade que o site
  #   declarou: a sessao seguinte nao o reencontraria e o visitante viraria cadastro novo, em
  #   silencio. Ele esta em `@attributes_to_update`, entao a interseccao sozinha nao bastaria.
  # · `avatar_url` — NAO e coluna de `contacts` (o avatar e ActiveStorage, preenchido por
  #   `enqueue_avatar_job`). `@contact[:avatar_url] = nil` levantaria `MissingAttributeError`.
  #   Hoje ele tambem nao esta em `@attributes_to_update`, mas depender disso seria depender de uma
  #   lista que existe por outro motivo.
  #
  # O VALOR IMPORTA e nao e detalhe de estilo: `email` e `phone_number` vao a `nil` porque a coluna
  # e nullable e os indices unicos por conta contam com NULL — string vazia colidiria no segundo
  # contato que fosse "apagado". `name` vai a `''`, que e o default da coluna: ela nao e nullable
  # por convencao aqui e o resto do produto trata `contact.name` como string.
  CLEARABLE_ATTRIBUTES = { name: '', email: nil, phone_number: nil }.freeze

  def update_contact
    @contact.attributes = params.slice(*@attributes_to_update).reject do |_k, v|
      v.blank?
    end.merge({ custom_attributes: custom_attributes, additional_attributes: additional_attributes })
    # blank identifier or email will throw unique index error
    # TODO: replace reject { |_k, v| v.blank? } with compact_blank when rails is upgraded
    clear_requested_attributes
    @contact.discard_invalid_attrs if discard_invalid_attrs
    @contact.save! if @contact.changed?
    auto_provision_custom_attribute_definitions
    enqueue_avatar_job
  end

  # Bloco 5.17 — a SUBSTITUICAO de verdade do verbo `set…`.
  #
  # O `reject(&:blank?)` da linha de cima existe para nao gravar vazio por acidente (identifier ou
  # email em branco batem no indice unico por conta). Ele e por isso mesmo o motivo de "substitui"
  # nunca ter substituido nada: campo vazio nao chegava, e campo ausente e indistinguivel de campo
  # que o site quer apagar. `clear_attributes` desfaz esse empate com um pedido NOMEADO, e por isso
  # roda DEPOIS — apagar antes seria desfeito pela atribuicao acima.
  #
  # DUAS TRAVAS, e as duas sao o que torna isto seguro numa rota publica:
  #
  # 1. `CLEARABLE_ATTRIBUTES` — so os quatro campos de topo do contato. Um chamador que mandasse
  #    `clear_attributes: ['identifier']` ou o nome de qualquer outra coluna nao apaga nada.
  # 2. `@attributes_to_update` — o que as regras de fusao ja decidiram NAO tocar continua intocado.
  #    Sem esta interseccao, uma sessao sob `identity_enforcement` estrito teria a fusao por e-mail
  #    recusada (`refuse_merge_under_enforcement?` tira `:email` da lista) e ainda assim conseguiria
  #    APAGAR o e-mail do dono do cadastro — a recusa protegeria a leitura e deixaria a escrita
  #    destrutiva passar, que e pior que nao ter recusa nenhuma.
  def clear_requested_attributes
    solicitados = Array(params[:clear_attributes]).map(&:to_sym)
    permitidos = solicitados & CLEARABLE_ATTRIBUTES.keys & @attributes_to_update
    return if permitidos.empty?

    # `params` vence a lista: o campo que o site MANDOU nesta mesma chamada foi gravado acima e nao
    # e candidato a apagamento. Sem isto, um payload com `email` presente e `email` na lista
    # dependeria da ordem para decidir, e ordem nao e contrato.
    permitidos.each do |key|
      next if params[key].present?

      @contact[key] = CLEARABLE_ATTRIBUTES[key]
    end
  end

  # B6: sem definicao, a chave que o site mandou fica no jsonb e nao aparece em
  # lugar nenhum do painel nem no filtro. Provisiona so o que veio nesta chamada.
  def auto_provision_custom_attribute_definitions
    return if params[:custom_attributes].blank?

    CustomAttributes::AutoProvisionService.new(
      account: account,
      attribute_model: :contact_attribute,
      custom_attributes: params[:custom_attributes]
    ).perform
  end

  def enqueue_avatar_job
    return unless params[:avatar_url].present? && !@contact.avatar.attached?
    return unless url_valid?(params[:avatar_url])

    Avatar::AvatarFromUrlJob.perform_later(@contact.class.name, @contact.id, params[:avatar_url])
  end

  def merge_contact(base_contact, merge_contact)
    return base_contact if base_contact.id == merge_contact.id

    ContactMergeAction.new(
      account: account,
      base_contact: base_contact,
      mergee_contact: merge_contact
    ).perform
  end

  # Bloco 4.17: chave marcada como "exige origem verificada" nao e escrita por sessao sem
  # assinatura conferida. A recusa e por chave: as demais do mesmo payload seguem gravando.
  def custom_attributes
    return @contact.custom_attributes if params[:custom_attributes].blank?

    permitidas = CustomAttributes::OriginGate.new(
      account: account,
      attribute_model: :contact_attribute,
      verified: verified_origin
    ).filter(params[:custom_attributes]).allowed

    (@contact.custom_attributes || {}).deep_merge(permitidas)
  end

  def additional_attributes
    return @contact.additional_attributes if params[:additional_attributes].blank?

    (@contact.additional_attributes || {}).deep_merge(params[:additional_attributes].stringify_keys)
  end
end
