# frozen_string_literal: true

# Protege o VALOR das variáveis de um template marcado como sigiloso na caixa.
#
# O caso que originou isto: a Fábrica dispara código de autenticação para assinatura de
# contrato pelo mesmo número que os 21 agentes usam para atender. O código não aparece na
# bolha (o `content` dessas mensagens é vazio), mas viajava em texto puro em
# `additional_attributes.template_params.processed_params`, que o `_message.json.jbuilder`
# serializa inteiro e o `Message#push_event_data` empurra pelo websocket, porque ele faz
# `attributes.symbolize_keys` e leva TODA coluna junto. Ou seja, estava no navegador de
# quem abrisse o devtools, no export, no backup e na busca.
#
# POR QUE PROTEGER NA ESCRITA, E NÃO ESCONDER NA LEITURA
#
# Esconder na leitura significaria repetir o filtro em cada ponto que lê mensagem. O
# próprio fork já documenta o custo disso no `AgentMessageIsolation`: "precisa ser
# reaplicado em CADA ponto de leitura". São cinco hoje (MessageFinder, preview da lista,
# histórico do contato, busca, ActionCable) e cada tela nova vira um vazamento futuro.
# Protegendo na escrita não existe nada para vazar: o que está gravado já é a máscara.
#
# COMO FUNCIONA
#
# Na criação da mensagem o valor real sai de `processed_params`, que fica com a máscara, e
# vai cifrado para `secret_params` na MESMA estrutura. O envio decifra na hora de montar o
# payload da Meta.
#
# O blob FICA guardado, porque o administrador precisa ler o valor depois. É a decisão do
# dono do produto, tomada com o custo na mesa: o valor continua existindo no banco e no
# backup, e quem for administrador da conta consegue ler o código que assina contrato.
# Em troca, ele nunca sai do servidor para quem não é administrador, e nunca vai pelo
# websocket, que não tem como saber quem está do outro lado.
#
# Quem revela é a LEITURA, não o armazenamento: `content_for` e `sanitized_attributes`
# decidem por espectador. Fora daí, o que está gravado é máscara.
#
# Se a chave existir e não decifrar, o envio FALHA em vez de mandar a máscara. Mandar
# "••••" como código seria pior do que não mandar: o cliente receberia um código inválido
# sem ninguém saber por quê.
module Spx::SecretTemplateParams
  MASK = '••••'
  # Chaves que descrevem a ESTRUTURA do parâmetro, não o conteúdo dele. Mascarar `media_type`
  # quebraria o envio (a Meta valida o tipo) sem esconder nada de ninguém.
  STRUCTURAL_KEYS = %w[media_type media_name type].freeze
  SECRET_KEY = 'secret_params'
  PROCESSED_KEY = 'processed_params'

  class RevealError < StandardError; end

  module_function

  # A caixa marcou este template como sigiloso? Sem template_params ou sem nome, não.
  def secret?(inbox, template_params)
    return false if inbox.blank? || template_params.blank?

    nome = template_params['name'] || template_params[:name]
    return false if nome.blank?

    # Lido direto do jsonb, como o `allowed_template_names` que divide a mesma tela: a
    # chave é da feature, não do modelo, e o Inbox já está no teto do ClassLength.
    Array(inbox.additional_attributes&.[]('secret_template_names')).include?(nome)
  end

  # Recebe os template_params crus e devolve a versão que PODE ser gravada: valores
  # mascarados em `processed_params` e o original cifrado em `secret_params`.
  def protect(template_params)
    params = template_params.deep_dup
    processed = params[PROCESSED_KEY]
    return params if processed.blank?

    params[SECRET_KEY] = encryptor.encrypt_and_sign(processed.to_json)
    params[PROCESSED_KEY] = mask(processed)
    params
  end

  # Devolve os template_params com os valores reais de volta, para montar o payload da Meta.
  # Sem `secret_params` é no-op: template comum passa direto.
  def reveal(template_params)
    return template_params if template_params.blank?

    blob = template_params[SECRET_KEY]
    return template_params if blob.blank?

    params = template_params.deep_dup
    params[PROCESSED_KEY] = JSON.parse(encryptor.decrypt_and_verify(blob))
    params.delete(SECRET_KEY)
    params
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature, JSON::ParserError => e
    raise RevealError, "nao foi possivel decifrar os parametros sigilosos: #{e.class}"
  end

  # A conversa existe SÓ para levar disparo protegido? Assinatura medida na Fábrica: as
  # atividades da automação ("Atribuído a triagem", "admin atribuiu a si mesmo") mais a
  # própria saída, e nenhuma entrada. Conversa com gente falando não bate.
  #
  # Três lugares perguntam isto, e é o mesmo conceito nos três: o envio (para tirar da
  # fila), o CSAT e o NPS (para não mandar pesquisa de satisfação a quem só recebeu um
  # código). Sem essa trava, na primeira VM com pesquisa ligada o cliente receberia
  # "de 0 a 10, como foi seu atendimento?" logo depois do código de autenticação.
  def dispatch_only?(conversation)
    return false if conversation.blank?
    return false if conversation.messages.incoming.exists?

    protegidas = conversation.messages.outgoing.where("additional_attributes->'template_params' IS NOT NULL")
    return false if protegidas.none?

    conversation.messages.outgoing.where("additional_attributes->'template_params' IS NULL").none?
  end

  # A mensagem tem valor protegido? Usado pela serialização e pelo websocket.
  def protected?(message)
    message.additional_attributes&.dig('template_params', SECRET_KEY).present?
  end

  # O `additional_attributes` como ele PODE sair do servidor para este espectador.
  #
  # O blob sai SEMPRE, para todo mundo: não há motivo para mandar texto cifrado ao
  # navegador, e mandar seria oferecer o alvo. Para administrador, o valor real entra no
  # lugar da máscara; para o resto, fica a máscara.
  def sanitized_attributes(message, viewer)
    atributos = message.additional_attributes
    return atributos unless protected?(message)

    params = atributos['template_params']
    params = admin?(viewer) ? reveal(params) : params.except(SECRET_KEY)
    atributos.merge('template_params' => params)
  rescue RevealError
    atributos.merge('template_params' => atributos['template_params'].except(SECRET_KEY))
  end

  # O texto da bolha para este espectador. O agente vê o rastro; o administrador vê o
  # rastro com o valor. Sai por `content` de propósito: assim a bolha, a busca e o export
  # já respeitam a regra sem precisar de componente novo na tela.
  def content_for(message, viewer)
    return message.content unless protected?(message) && admin?(viewer)

    valores = revealed_values(message.additional_attributes['template_params'])
    return message.content if valores.blank?

    I18n.t('conversations.secret_template.trace_admin', valores: valores.join(' · '))
  rescue RevealError
    message.content
  end

  # Os valores reais, sem repetição e sem as chaves estruturais. Um código de autenticação
  # aparece duas vezes (corpo e botão da URL) e não faz sentido mostrar duas vezes.
  def revealed_values(template_params)
    processed = reveal(template_params)[PROCESSED_KEY]
    return [] if processed.blank?

    processed.values.flat_map { |valor| leaf_values(valor) }.compact_blank.uniq
  end

  def leaf_values(valor)
    case valor
    when Hash then valor.reject { |chave, _| STRUCTURAL_KEYS.include?(chave.to_s) }.values.map(&:to_s)
    when Array then valor.flat_map { |item| leaf_values(item) }
    else [valor.to_s]
    end
  end

  # Administrador DA CONTA, não do sistema: a mesma leitura que o AgentMessageIsolation usa
  # para isentar. Sem User (job, widget, API pública) nunca é administrador.
  def admin?(viewer)
    viewer.is_a?(User) && viewer.administrator?
  end

  def mask(processed)
    processed.transform_values do |valor|
      case valor
      when Hash then mask_hash(valor)
      when Array then valor.map { |item| item.is_a?(Hash) ? mask_hash(item) : MASK }
      else MASK
      end
    end
  end

  def mask_hash(hash)
    hash.to_h { |chave, valor| [chave, STRUCTURAL_KEYS.include?(chave.to_s) ? valor : MASK] }
  end

  # Chave derivada do `secret_key_base`, que toda VM já tem. Deliberadamente NÃO usa o
  # ActiveRecord::Encryption: aquele depende de três variáveis de ambiente próprias
  # (`ACTIVE_RECORD_ENCRYPTION_*`) que nem toda VM da frota configurou, e uma proteção que
  # some conforme a VM não é proteção.
  def encryptor
    @encryptor ||= begin
      chave = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base)
                                         .generate_key('spx/secret_template_params', 32)
      ActiveSupport::MessageEncryptor.new(chave)
    end
  end
end
