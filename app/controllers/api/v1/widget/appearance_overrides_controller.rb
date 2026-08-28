# frozen_string_literal: true

# Bloco 3.18 — ONDE A PRECEDENCIA VIRA COISA QUE O OPERADOR CONSEGUE VER.
#
# A regra e "o banco e o padrao, o `chatwootSettings` do site sobrescreve, e a tela declara".
# As duas primeiras partes moram no SDK. A terceira precisa de um fato gravado, porque a tela de
# aparencia roda no painel e NAO tem como ler o HTML do site do cliente — ela so sabe o que o
# widget, que roda la, contar. Ate aqui `AppearancePage.vue:67` lia
# `additional_attributes['widget_appearance_overrides']` e essa chave nao tinha produtor nenhum:
# `overriddenFields` era `[]` para sempre e o aviso de override nunca aparecia.
#
# AUTENTICACAO: a mesma de todo o widget (`X-Auth-Token` -> `@contact_inbox`), como o 4.18 e o 4.21.
# A inbox NAO vem do corpo — vem do token —, senao qualquer visitante poderia escrever no painel de
# uma conta alheia.
#
# O QUE ESTE ENDPOINT ACEITA, E POR QUE ISSO E POUCO
#
# So nomes de campo, e so os que estao em `OVERRIDABLE_BY_SITE`. Nao entra valor nenhum: o pior que
# um cliente adulterado consegue e fazer o painel do PROPRIO cliente exibir (ou deixar de exibir) um
# aviso amarelo sobre um campo que existe no schema. Nao ha PII, nao ha texto livre e nao ha caminho
# para escrever fora dessa lista fechada — `additional_attributes` inteiro vai para o HTML de toda
# pagina do cliente, entao aceitar string livre aqui seria abrir um canal de injecao.
#
# ESCRITA SO QUANDO MUDA — E O QUE ISSO COMPRA NAO E O QUE PARECE
#
# Este relatorio sai a CADA boot do widget, ou seja, a cada pageview de cada visitante de cada site.
# A tentacao e dizer que o atalho evita um `UPDATE` por pageview; MEDIDO, ele nao evita: o proprio
# ActiveRecord ja nao emite `UPDATE` quando nenhum atributo mudou, e tirar a comparacao daqui NAO
# faz o teste de `updated_at` cair. O que ela compra e outra coisa, e ha um exemplo so para ela:
# sem o atalho o `update!` ainda RODA AS VALIDACOES, e uma inbox com jsonb legado invalido passaria
# a responder 422 a cada boot — para reenviar uma lista que ja estava gravada e correta.
class Api::V1::Widget::AppearanceOverridesController < Api::V1::Widget::BaseController
  ATTRIBUTE = 'widget_appearance_overrides'

  def create
    return head :unprocessable_entity if inbox.blank? || invalid_fields?
    return head :no_content if inbox.additional_attributes[ATTRIBUTE] == reported_fields

    # `update!` e nao `update_column` de proposito: a escrita precisa passar pelos callbacks e
    # mexer no `updated_at`, senao o painel poderia continuar servindo a inbox de um cache e o
    # aviso so apareceria quando outra coisa qualquer tocasse a linha.
    #
    # NAO ha `rescue` aqui, e a ausencia foi MEDIDA. Uma inbox pode ter `widget_appearance` gravado
    # antes do schema (ou por caminho que o burlou), e nesse caso a validacao do modelo recusa
    # QUALQUER `update!` — inclusive este, que nem toca naquela chave. Como o relatorio sai a cada
    # boot do widget, isso viraria um erro por pageview. Ja resolvem DUAS camadas existentes: o
    # `rescue_from ActiveRecord::RecordInvalid` de `RequestExceptionHandler` e, atras dele, o
    # mapeamento padrao do Rails (`rescue_responses`), que tambem devolve 422 — sabotar so o
    # primeiro nao muda o resultado. Um `rescue` proprio aqui seria codigo morto.
    inbox.update!(additional_attributes: inbox.additional_attributes.merge(ATTRIBUTE => reported_fields))

    head :no_content
  end

  private

  def invalid_fields?
    raw_fields = params[:fields]

    # Ausencia NAO e lista vazia. `fields: []` e uma medicao ("o site nao sobrescreve nada") e apaga
    # um aviso velho; `fields` ausente e um cliente que nao sabe do que esta falando, e recusar e o
    # que impede um chamador antigo de zerar a lista sem querer.
    return true unless raw_fields.is_a?(Array)

    (raw_fields.map(&:to_s) - WidgetAppearanceSchema::OVERRIDABLE_BY_SITE.keys).any?
  end

  # Ordenado pelo schema, nunca pela ordem de chegada: o valor gravado e comparado com o anterior
  # para decidir se ha escrita, e duas listas com os mesmos campos em ordens diferentes fariam toda
  # requisicao parecer mudanca. `uniq` pela mesma razao.
  def reported_fields
    @reported_fields ||= WidgetAppearanceSchema::OVERRIDABLE_BY_SITE.keys & params[:fields].map(&:to_s).uniq
  end
end
