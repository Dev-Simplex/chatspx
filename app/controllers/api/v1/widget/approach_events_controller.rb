# frozen_string_literal: true

# Bloco 4.21 — a instrumentacao dos tres niveis de abordagem.
#
# O motivo pelo qual os tres niveis existem: cada exibicao, dispensa, abertura e conversao
# vira dado, e uma consulta passa a responder "qual nivel converte mais NESTA conta" sem
# abrir o console de ninguem. A discussao sobre auto-open deixa de ser opiniao.
#
# AUTENTICACAO: a mesma de todo o widget (`X-Auth-Token` -> `@contact_inbox`), como o 4.18.
# A sessao NAO vem do corpo. Ela e a metade da chave de idempotencia, e aceita-la do corpo
# deixaria um cliente adulterado colidir com a chave de outro visitante e APAGAR o evento
# dele — a dedup viraria uma ferramenta de suprimir dado alheio.
#
# A ARMADILHA HERDADA, E COMO ELA E CONSUMIDA EM VEZ DE CONTORNADA
#
# O contrato (docs/tracking/contrato-de-eventos.md §4.2) diz: o mesmo fato registrado duas
# vezes e um registro so, e a trava e o indice unico `(account_id, name, dedup_key)`. Aqui a
# retentativa nao vem de um job — vem da rede e do proprio visitante: reenvio do POST,
# `handleSendMessage` disparado tres vezes porque a pessoa mandou tres mensagens seguidas.
#
# Por isso a `dedup_key` e passada EXPLICITAMENTE e deriva do fato, nunca do relogio:
#
#     approach:<source_id da sessao>:<ordinal da abordagem>
#
# Omiti-la e um defeito MEDIDO, nao suposto — sabotando esta linha, tres exemplos do spec
# ficam vermelhos, e eles mostram os dois danos, que sao opostos:
#
#   · CONTA DEMAIS — a derivacao padrao usa `occurred_at.to_i`, e o retry cai noutro segundo:
#     tres mensagens seguidas do visitante viram tres conversoes;
#   · CONTA DE MENOS — duas abordagens GENUINAS ao mesmo visitante dentro do mesmo segundo
#     compartilham a chave derivada e viram uma linha so.
#
# O que a derivacao padrao NAO faz, e vale registrar porque a versao anterior deste comentario
# dizia que fazia: ela nao mistura visitantes diferentes. O assunto dela cai para `contact_id`,
# que este endpoint passa. O ordinal resolve os dois danos acima, nao esse terceiro.
class Api::V1::Widget::ApproachEventsController < Api::V1::Widget::BaseController
  # Quatro fatos, e o SERVIDOR e quem compoe o nome. O cliente manda a etapa, nunca o nome:
  # e a mesma licao do `EventsController`, onde nome vindo do site do cliente ia direto para
  # o barramento. Aqui um nome livre entraria no GA4 e no Meta do cliente.
  STAGES = %w[shown dismissed opened converted].freeze
  NAME_PREFIX = 'chatspx_approach_'
  # Teto do ordinal: e um inteiro pequeno vindo do navegador, e a escada de familiaridade
  # acaba no terceiro degrau. Aceitar 2**31 seria aceitar lixo com cara de dado.
  MAX_ORDINAL = 99

  def create
    return head :unprocessable_entity unless valid_request?

    Tracking::EventRecorder.record!(
      name: "#{NAME_PREFIX}#{stage}",
      account: inbox.account,
      inbox: inbox,
      contact: @contact,
      properties: properties,
      source: :widget,
      dedup_key: "approach:#{@contact_inbox.source_id}:#{ordinal}"
    )

    head :no_content
  end

  private

  def valid_request?
    inbox.present? &&
      STAGES.include?(stage) &&
      approaches_known? &&
      ordinal.between?(1, MAX_ORDINAL)
  end

  # Os dois niveis sao validados contra o MESMO vocabulario do schema 3.20. Se um dia a
  # escada ganhar um degrau, ela ganha em um lugar so e este endpoint acompanha.
  #
  # `all?` e nao interseccao: o caso normal e os DOIS serem iguais (nivel nao degradado), e
  # `APPROACHES & %w[bold bold]` devolve UM elemento. Uma checagem de tamanho recusaria
  # justamente a abordagem que nao caiu — o teste `degraded: false` pegou isso.
  def approaches_known?
    [approach, approach_configured].all? { |nivel| WidgetTriggersSchema::APPROACHES.include?(nivel) }
  end

  # Sem PII, e nao por sorte: sao tres campos fechados, todos vocabulario da configuracao.
  # A regra RC5/5.14 e "nomes de campo, nunca valores", e aqui nem nome de campo do cliente
  # entra. `degraded` e derivado em vez de recebido — quem calcula uma coisa a partir das
  # outras duas nao pode discordar delas.
  def properties
    {
      approach: approach,
      approach_configured: approach_configured,
      degraded: approach != approach_configured
    }
  end

  def stage
    params[:stage].to_s
  end

  def approach
    params[:approach].to_s
  end

  def approach_configured
    params[:approach_configured].to_s
  end

  def ordinal
    params[:ordinal].to_i
  end
end
