# O que o widget RECEBE, derivado do que esta gravado (blocos 3.03, 3.04, 3.18, 3.20).
#
# Separado de `WidgetConfigurable` de proposito: la mora o que RECUSA escrita errada, aqui o que
# ENTREGA leitura completa. Toda leitura aqui e derivada — nenhuma delas escreve no banco, porque a
# regra A4 vale para as quatro chaves: `nil` tem significado, e backfill nao acontece.
module WidgetConfigResolvable
  extend ActiveSupport::Concern

  # Leitura derivada, nunca backfill (A4): inbox sem a chave se comporta como "support",
  # que e literalmente o comportamento de hoje.
  def resolved_widget_profile
    widget_profile.presence || 'support'
  end

  # Bloco 3.20 (D1): a abordagem lida de forma derivada. Inbox sem a chave e `bold` com degradacao
  # ligada — que e a decisao de produto, nao o comportamento de hoje; nao ha migration nem backfill
  # (A4), e o SDK recebe os tres campos porque a avaliacao e dele (A5).
  # `approach_mobile` NUNCA herda `aggressive` do desktop: em celular o painel cobre a tela inteira.
  def resolved_widget_approach
    stored = widget_triggers.is_a?(Hash) ? widget_triggers : {}
    desktop = stored['approach'].presence || WidgetTriggersSchema::DEFAULT_APPROACH
    mobile = stored['approach_mobile'].presence || desktop
    mobile = WidgetTriggersSchema::DEFAULT_APPROACH unless WidgetTriggersSchema::MOBILE_APPROACHES.include?(mobile)
    degrade = stored.fetch('degrade_on_return', WidgetTriggersSchema::DEFAULT_DEGRADE_ON_RETURN)

    { 'approach' => desktop, 'approach_mobile' => mobile, 'degrade_on_return' => degrade }
  end

  # Bloco 3.04: os gatilhos entregues ao widget, com a abordagem JA RESOLVIDA por dentro. A abordagem
  # nao ganha chave propria no payload de proposito (A15): dois lugares para o mesmo fato obrigariam o
  # SDK a ler dois caminhos para tomar uma decisao so, e e assim que as duas pontas divergem.
  def resolved_widget_triggers
    stored = widget_triggers.is_a?(Hash) ? widget_triggers : {}

    stored.merge(resolved_widget_approach)
  end

  # Bloco 3.04: o que o widget recebe de tracking e uma projecao por lista branca, nunca o hash cru.
  def public_widget_tracking
    WidgetTrackingProjection.public_view(widget_tracking)
  end

  # A aparencia entregue ao widget e sempre COMPLETA: o banco e o padrao, e o padrao tem de existir
  # mesmo na inbox que nunca abriu a tela (regra A4 — sem migration e sem backfill).
  # Chave fora do schema e descartada aqui: o que sobrou de uma versao anterior nao vaza para o site.
  def resolved_widget_appearance
    stored = widget_appearance.is_a?(Hash) ? widget_appearance : {}
    merged = WidgetAppearanceSchema::DEFAULTS.merge(stored.slice(*WidgetAppearanceSchema::DEFAULTS.keys))

    merged.merge('launcher_icon' => resolved_launcher_icon(merged['launcher_icon']))
  end

  # Bloco 4.08 — o numero da saida para o WhatsApp, ja SO COM DIGITOS.
  #
  # Derivada como as irmas (A4): inbox sem a chave devolve string vazia, e string vazia esconde o
  # botao — que e o comportamento de hoje, sem migration e sem backfill.
  #
  # Por que os montadores chamam ISTO e nao `widget_exit['whatsapp_number']` na mao: sao DOIS
  # montadores (`show.html.erb` e `configs/create.json.jbuilder`), e duas leituras escritas a mao
  # sao duas leituras que divergem. Ja aconteceu nesta base — `teaserText` existia so no ERB.
  # Uma fonte, dois consumidores, e a suite de paridade cobrando as duas pontas.
  def whatsapp_exit_number
    stored = widget_exit.is_a?(Hash) ? widget_exit : {}

    stored['whatsapp_number'].to_s.gsub(/\D/, '')
  end

  # Bloco 3.19 — o icone do lancador, ja resolvido, porque o host CONSOME a decisao e nunca a
  # recalcula (o mesmo padrao de `tokens` e `resolved_widget_approach`).
  #
  # O que sai daqui:
  #   - modo desconhecido           -> `default`, sempre. Nunca um lancador vazio.
  #   - `image` com imagem anexada  -> `{mode, url}` com a URL ABSOLUTA no nosso dominio
  #   - `image` sem imagem anexada  -> `default`. E o gemeo servidor do `onerror` do SDK: nem o site
  #                                    do cliente fica sem canal de contato, nem o navegador
  #                                    do visitante gasta uma requisicao para descobrir um 404.
  #   - `agent_photo`               -> o modo puro. Quem tem o avatar da inbox e o host (`avatarUrl`).
  #
  # A projecao e ANINHADA de proposito: `slice` so filtra o primeiro nivel, e uma chave sobrando
  # DENTRO de `launcher_icon` (de uma versao anterior, ou de uma escrita direta no banco) iria
  # inteira para o HTML de toda pagina do site do cliente. Aqui so passam `mode` e `url`.
  def resolved_launcher_icon(stored)
    mode = WidgetAppearanceSchema.launcher_icon_mode(stored)
    fallback = WidgetAppearanceSchema::DEFAULTS['launcher_icon']
    return fallback unless WidgetAppearanceSchema::LAUNCHER_ICONS.include?(mode)
    return mode unless mode == 'image'

    url = launcher_icon_image_url
    url.present? ? { 'mode' => 'image', 'url' => url } : fallback
  end
end
