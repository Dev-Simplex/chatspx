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
# payload da Meta e apaga a chave depois que a mensagem sai. Enquanto ela existe, é um blob
# ilegível: serializar ou empurrar pelo websocket não entrega nada.
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

  # Chamado depois que a mensagem SAIU: o valor real já cumpriu a função e some do banco.
  # A máscara continua em `processed_params`, então o rastro (quantas variáveis, qual
  # botão) permanece legível sem entregar o conteúdo.
  def forget!(message)
    params = message.additional_attributes&.dig('template_params')
    return false if params.blank? || params[SECRET_KEY].blank?

    params = params.except(SECRET_KEY)
    message.additional_attributes = message.additional_attributes.merge('template_params' => params)
    message.save!
    true
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
