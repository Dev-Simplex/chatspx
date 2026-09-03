# frozen_string_literal: true

# Importa uma campanha legada de chat ao vivo como GATILHO do motor novo (bloco 4.22).
#
# ─── É RAMPA, NÃO CORTE ──────────────────────────────────────────────────────────────
# O bloco não desliga as campanhas: ele dá precedência ao motor novo e oferece um
# caminho de mão única para quem quiser migrar. É o mesmo padrão da tela de Automações,
# onde o "modo antigo" continua listado e editável enquanto o cliente decide.
#
# ─── A REGRA QUE O ACEITE COBRA: NUNCA AS DUAS LIGADAS ───────────────────────────────
# Importar **cria o gatilho equivalente E desativa a campanha**, numa transação. As duas
# metades juntas ou nenhuma — se a escrita do gatilho falhasse depois de a campanha ser
# desativada, o cliente ficaria sem nenhuma mensagem proativa e sem saber por quê; se a
# campanha continuasse ligada depois de o gatilho nascer, o visitante teria dois convites
# e o 4.22 inteiro perderia o sentido.
#
# ─── O QUE "EQUIVALENTE" QUER DIZER, CAMPO A CAMPO ───────────────────────────────────
# A campanha legada carrega dois critérios em `trigger_rules`, e só dois:
#
#   time_on_page (segundos) → gatilho `time_on_page`, ligado em desktop E mobile com o
#                             mesmo valor. A campanha nunca distinguiu plataforma, e
#                             inventar uma distinção na importação mudaria o
#                             comportamento sem o cliente pedir.
#   url (string)            → `audience.url` com operador `contains`. `contains` e não
#                             `equals` porque a campanha legada casa por prefixo/inclusão
#                             (`campaign.rb:143-145`), e `equals` deixaria de disparar em
#                             páginas que hoje disparam — regressão silenciosa na migração.
#
# O TEXTO NÃO É COPIADO, e é decisão: pelo 4.05 a mensagem do convite **é** a campanha
# vinculada ("campanha é mensagem, gatilho é momento"). Copiar o texto para dentro de
# `widget_triggers` criaria a segunda cópia que aquele bloco existe para não ter — e o
# schema recusaria a chave (`additionalProperties: false`).
class Widget::CampaignImportService
  class NotImportable < StandardError; end

  # Sem tempo declarado a campanha dispara assim que a página carrega. O gatilho novo
  # precisa de um número, e 0 é o número honesto para "imediatamente".
  DEFAULT_TIME_ON_PAGE = 0

  def initialize(campaign:)
    @campaign = campaign
    @inbox = campaign&.inbox
  end

  def perform
    validate!

    ActiveRecord::Base.transaction do
      @inbox.update!(additional_attributes: attributes_with_triggers)
      @campaign.update!(enabled: false)
    end

    @inbox.reload
  end

  private

  def validate!
    raise NotImportable, 'campanha inexistente' if @campaign.blank?
    raise NotImportable, 'a importação só vale para campanha de chat ao vivo' unless live_chat?
  end

  # `ongoing` numa inbox Website é exatamente a campanha que o widget dispara sozinho —
  # a mesma que o `getLiveChatCampaigns` do painel lista. Campanha de disparo (one_off,
  # WhatsApp) não tem gatilho de página para traduzir.
  def live_chat?
    @campaign.ongoing? && @inbox.present? && @inbox.web_widget?
  end

  def attributes_with_triggers
    (@inbox.additional_attributes || {}).merge('widget_triggers' => merged_triggers)
  end

  # O gatilho importado ENTRA no que já existe em vez de substituir: uma conta pode
  # importar duas campanhas, e a segunda não pode apagar a primeira. Gatilho do mesmo
  # `id` é substituído (não há dois `time_on_page` no schema).
  def merged_triggers
    atual = (@inbox.additional_attributes || {})['widget_triggers']
    atual = {} unless atual.is_a?(Hash)

    outros = Array(atual['triggers']).reject { |t| t.is_a?(Hash) && t['id'] == 'time_on_page' }

    atual.merge(
      'enabled' => true,
      'triggers' => outros + [time_on_page_trigger],
      'audience' => audience_for(atual)
    ).compact
  end

  def time_on_page_trigger
    segundos = tempo_na_pagina
    plataforma = { 'enabled' => true, 'value' => segundos }
    { 'id' => 'time_on_page', 'desktop' => plataforma, 'mobile' => plataforma.dup }
  end

  def tempo_na_pagina
    bruto = regras['time_on_page']
    segundos = bruto.to_i
    return DEFAULT_TIME_ON_PAGE if bruto.blank? || segundos.negative?

    # O schema recusa acima de 86.400; um valor maior no legado vira o teto em vez de
    # derrubar a importação inteira com um 422 que o cliente não sabe consertar.
    segundos.clamp(0, 86_400)
  end

  # `audience` só é escrita quando há URL para escrever. Uma `audience` vazia é diferente
  # de `audience` ausente para quem lê o schema depois, e a campanha sem URL vale para o
  # site inteiro — que é o que a ausência já significa.
  def audience_for(atual)
    url = regras['url'].to_s.strip
    return atual['audience'] if url.blank?

    existente = atual['audience'].is_a?(Hash) ? atual['audience'] : {}
    existente.merge('url' => { 'operator' => 'contains', 'values' => [url] })
  end

  def regras
    @regras ||= @campaign.trigger_rules.is_a?(Hash) ? @campaign.trigger_rules : {}
  end
end
