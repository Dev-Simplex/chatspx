# frozen_string_literal: true

# Bloco 5.12 — o modo "sem PII", que hoje e o UNICO modo que a fila server-side sabe operar.
#
# A verificacao 2 do plano 25 (o DPA: contrato juridico que cobre mandar PII hasheada a Meta e ao
# Google por conta do cliente) NAO EXISTE. Enquanto ela nao existir, nenhum campo de pessoa pode
# sair daqui — e a trava e por CONSTRUCAO, nao por configuracao de conta: `DPA_SIGNED` e uma
# constante `false`, entao nao ha combinacao de credencial, flag ou payload que faca `em`, `ph`,
# `fn` ou `ln` chegar ao fio.
#
# Ligar o modo com PII (o resto do bloco 5.11) e mudar ESTA constante, num arquivo so, depois de o
# juridico responder as tres perguntas da §Parte D. Ate la o caminho existe, e testado, e nao
# entrega — que e bem diferente de nao existir.
#
# O que se perde: o EMQ cai da faixa "Great" para "OK". O que se ganha: o server-side ja recupera
# a parte perdida por bloqueador, que e a razao de o plano mandar construir este modo PRIMEIRO.
module Tracking::PiiPolicy
  # Vocabulario CANONICO dos campos de pessoa (T-C5.3). Deliberadamente o mesmo em todo destino,
  # mesmo quando o nome no fio muda (`em` na Meta, `hashedEmail` no Google Ads): o log de auditoria
  # fala UMA lingua, senao "o campo `em` saiu?" viraria tres perguntas diferentes por destino.
  PERSON_FIELDS = %w[em ph fn ln ct st zp country].freeze

  # O que o modo sem PII AINDA manda: identificador de navegador, de anuncio e o id opaco do
  # contato. Nenhum deles descreve a pessoa — de `external_id` nao se volta a um nome nem a um
  # e-mail, e e por isso que ele fica de fora da lista acima mesmo sendo hasheado.
  ANONYMOUS_FIELDS = %w[external_id fbp fbc gclid client_ip_address client_user_agent].freeze

  # A unica linha que o juridico destrava. Nao transforme em config de conta sem o DPA: seria
  # trocar uma trava que nao tem como falhar por uma que um clique errado desliga.
  DPA_SIGNED = false

  module_function

  def mode
    DPA_SIGNED ? :with_pii : :without_pii
  end

  def person_fields_allowed?
    DPA_SIGNED
  end

  # Os NOMES (nunca os valores) dos campos de pessoa que existiam e foram retidos. E o que o log de
  # auditoria guarda para que o aceite do 5.12 seja verificavel sem abrir o console de ninguem.
  def suppressed_from(available_field_names)
    return [] if person_fields_allowed?

    PERSON_FIELDS & Array(available_field_names).map(&:to_s)
  end
end
