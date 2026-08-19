# frozen_string_literal: true

# Bloco 4.17 — o portao de escrita por atributo.
#
# O 1.16 fez o dado que o site manda APARECER. Este bloco cuida do outro lado: nem todo
# atributo pode ser escrito por quem quer que esteja na pagina. Uma definicao marcada com
# `requires_verified_origin` so aceita escrita de uma sessao cuja identidade foi
# verificada por assinatura (`contact_inboxes.hmac_verified`).
#
# Duas decisoes que este arquivo carrega:
#
#   1. A recusa e POR CHAVE, nunca da requisicao inteira. Um `setCustomAttributes` que
#      manda cinco chaves, das quais uma e protegida, grava as quatro e recusa uma. Derrubar
#      a requisicao inteira faria o site do cliente parar de funcionar por causa de um
#      atributo que ele nem sabia estar protegido.
#   2. O valor protegido nao e sobrescrito NEM apagado — ele fica exatamente como estava.
#      "Nao altera o valor" e o aceite, e apagar tambem seria alterar.
#
# O gate cobre contato E conversa. A conversa e justamente a que o site escreve com mais
# liberdade: `widget/conversations#set_custom_attributes` nao tem assinatura nenhuma.
class CustomAttributes::OriginGate
  Result = Struct.new(:allowed, :refused, keyword_init: true) do
    def refused?
      refused.any?
    end
  end

  def initialize(account:, attribute_model:, verified:)
    @account = account
    @attribute_model = attribute_model.to_s
    @verified = verified
  end

  # `incoming` e o que a requisicao mandou. Devolve o que pode ser gravado e o que foi
  # recusado, para quem chamou decidir o que fazer com cada um.
  def filter(incoming)
    attributes = normalize(incoming)
    return Result.new(allowed: attributes, refused: []) if @verified || attributes.blank?

    protegidas = protected_keys & attributes.keys
    return Result.new(allowed: attributes, refused: []) if protegidas.empty?

    record(protegidas)
    Result.new(allowed: attributes.except(*protegidas), refused: protegidas)
  end

  # Para endpoint de SUBSTITUICAO, onde o que nao vem no payload sai.
  #
  # Nao basta recusar a escrita da chave protegida: omiti-la apagaria o valor, e apagar
  # tambem e alterar. Entao toda chave protegida que JA existia sobrevive, tenha vindo no
  # payload ou nao. Sem chave protegida no registro, o resultado e byte a byte o de antes.
  def replace(incoming:, existing:)
    resultado = filter(incoming)
    return resultado if @verified

    sobreviventes = normalize(existing).slice(*protected_keys)
    return resultado if sobreviventes.empty?

    Result.new(allowed: resultado.allowed.merge(sobreviventes), refused: resultado.refused)
  end

  private

  def normalize(incoming)
    return {} if incoming.blank?

    incoming.to_h.stringify_keys
  rescue StandardError
    {}
  end

  def protected_keys
    @protected_keys ||= CustomAttributeDefinition.protected_keys(account: @account, attribute_model: @attribute_model)
  end

  # "a tentativa fica registrada": a linha nomeia a conta, o modelo e as chaves recusadas,
  # que e o que alguem precisa para responder "quem tentou escrever o que".
  def record(keys)
    Rails.logger.warn(
      "[custom_attributes] escrita recusada por origem nao verificada account_id=#{@account.id} " \
      "modelo=#{@attribute_model} chaves=#{keys.sort.join(',')}"
    )
  end
end
