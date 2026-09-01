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
#      "Nao altera o valor" e o aceite, e apagar tambem seria alterar. Por isso o portao tem
#      DUAS portas, uma por forma de alterar: `filter` (escrita, que mescla) e `delete`
#      (exclusao explicita).
#
#      Houve uma terceira, `replace`, para o endpoint de SUBSTITUICAO — onde omitir a chave
#      protegida a apagaria. Ela sumiu com o bloco 5.08, que tornou
#      `widget/conversations#set_custom_attributes` uma MESCLA: sem substituicao no
#      caminho, nao ha omissao que apague, e a porta deixou de ter dono.
#
# CINCO superficies passam pelo portao — escrita e exclusao de contato e de conversa, mais a
# CRIACAO da conversa, que e a primeira que o visitante atravessa:
#
#   · widget/base#conversation_params (create)        -> filter   (sem assinatura)
#   · widget/conversations#set_custom_attributes      -> filter   (sem assinatura)
#   · widget/conversations#destroy_custom_attributes  -> delete   (sem assinatura)
#   · widget/contacts#update (ContactIdentifyAction)  -> filter
#   · widget/contacts#destroy_custom_attributes       -> delete   (sem assinatura)
#
# `widget/contacts#update` NAO entra sem assinatura nenhuma: ele tem
# `before_action :validate_hmac_for_identified_update` (contacts_controller.rb:14), que valida
# HMAC sempre que o pedido carrega `identifier` ou campo de amarracao de identidade. O portao
# ali cobre o resto do payload, nao a identidade.
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

  # Para endpoint de EXCLUSAO, que recebe uma LISTA DE CHAVES em vez de um payload.
  #
  # Apagar tambem e alterar. Sem esta porta, quem nao consegue ESCREVER a chave protegida
  # simplesmente a APAGA — e os dois endpoints de exclusao do widget
  # (`widget/conversations#destroy_custom_attributes` e `widget/contacts#destroy_custom_attributes`)
  # nao pedem assinatura nenhuma. A recusa continua sendo POR CHAVE: as demais chaves do
  # mesmo pedido sao apagadas normalmente.
  def delete(keys)
    chaves = normalize_keys(keys)
    return Result.new(allowed: chaves, refused: []) if @verified || chaves.empty?

    protegidas = protected_keys & chaves
    return Result.new(allowed: chaves, refused: []) if protegidas.empty?

    record(protegidas, 'exclusao')
    Result.new(allowed: chaves - protegidas, refused: protegidas)
  end

  private

  def normalize(incoming)
    return {} if incoming.blank?

    incoming.to_h.stringify_keys
  rescue StandardError
    {}
  end

  # A lista chega do corpo da requisicao: pode vir como array, como chave avulsa ou nula.
  # Chave de jsonb e sempre string, entao comparar como string e o que corresponde ao banco.
  def normalize_keys(keys)
    Array.wrap(keys).filter_map { |key| key.to_s.presence }
  end

  def protected_keys
    @protected_keys ||= CustomAttributeDefinition.protected_keys(account: @account, attribute_model: @attribute_model)
  end

  # "a tentativa fica registrada": a linha nomeia a conta, o modelo e as chaves recusadas,
  # que e o que alguem precisa para responder "quem tentou escrever o que".
  def record(keys, acao = 'escrita')
    Rails.logger.warn(
      "[custom_attributes] #{acao} recusada por origem nao verificada account_id=#{@account.id} " \
      "modelo=#{@attribute_model} chaves=#{keys.sort.join(',')}"
    )
  end
end
