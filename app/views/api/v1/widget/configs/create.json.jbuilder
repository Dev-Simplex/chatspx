json.website_channel_config do
  json.allow_messages_after_resolved @web_widget.inbox.allow_messages_after_resolved
  json.api_host ENV.fetch('FRONTEND_URL', nil)
  json.auth_token @token
  json.avatar_url @web_widget.inbox.avatar_url
  json.csat_survey_enabled @web_widget.inbox.csat_survey_enabled
  json.disable_branding @web_widget.inbox.account.feature_enabled?('disable_branding')
  json.enabled_features @web_widget.selected_feature_flags
  json.enabled_languages available_locales_with_name
  json.locale @web_widget.account.locale
  json.out_of_office_message @web_widget.inbox.out_of_office_message
  json.portal @web_widget.inbox.portal
  json.pre_chat_form_enabled @web_widget.pre_chat_form_enabled
  json.pre_chat_form_options @web_widget.pre_chat_form_options
  json.reply_time @web_widget.reply_time
  # Bloco 4.05 — o texto do teaser JA RESOLVIDO no servidor (campanha vinculada ->
  # welcome_tagline -> welcome_title). MESMA FONTE do `show.html.erb`: `#teaser_text`.
  #
  # Precisa existir AQUI pelo motivo que o comentario dos tokens abaixo ja explica: este
  # jbuilder e o substituto planejado do ERB. Chave que existe so num dos dois lados morre
  # em silencio no dia da troca — foi a suite de paridade (0.6) que cobrou, acusando
  # `teaserText` presente no ERB e ausente aqui.
  json.teaser_text @web_widget.teaser_text
  json.timezone @web_widget.inbox.timezone
  # Bloco 1.02 — os sete tokens de marca, calculados no SERVIDOR por luminância
  # WCAG. MESMA FONTE que o `<style>` e o `window.chatwootWebChannel` do
  # `show.html.erb`: `WidgetTokens.for(@web_widget)`. Duas chamadas ao mesmo
  # serviço, nunca duas fórmulas — fórmula duplicada é fórmula que diverge, que
  # é o defeito que a Onda 1 inteira existe para corrigir.
  #
  # Por que ISTO precisa existir aqui, e não é excesso de zelo: o
  # `widgets_controller.rb:1` carrega um TODO do upstream dizendo para APAGAR o
  # controller do ERB "once 'api/widget/config' end point is merged". Ou seja,
  # este jbuilder é o SUBSTITUTO PLANEJADO do `show.html.erb`. No dia em que essa
  # troca acontecer, um jbuilder sem `tokens` levaria junto o bloco 1.02 inteiro
  # — e o flash de cor errada voltaria sem que um único teste ficasse vermelho.
  #
  # A suíte de paridade (0.6) é quem cobra as duas pontas.
  json.tokens WidgetTokens.for(@web_widget).to_h
  json.utc_off_set ActiveSupport::TimeZone[@web_widget.inbox.timezone].now.formatted_offset
  json.website_name @web_widget.inbox.name
  json.website_token @web_widget.website_token
  json.welcome_tagline @web_widget.welcome_tagline
  json.welcome_title @web_widget.welcome_title
  json.widget_color @web_widget.widget_color
  json.working_hours @web_widget.inbox.working_hours
  json.working_hours_enabled @web_widget.inbox.working_hours_enabled
  # Bloco 3.04 — as mesmas chaves do `show.html.erb`, e a suite de paridade (0.6) cobra as duas
  # pontas: acrescentar aqui e esquecer la (ou o contrario) falha nomeando a chave e o arquivo.
  # As chaves de TOPO seguem a convencao de cada arquivo (snake_case aqui, camelCase no ERB); o
  # CONTEUDO e identico, porque quem consome os dois e o mesmo codigo do widget.
  json.widget_profile @web_widget.inbox.resolved_widget_profile
  json.profile_config WidgetProfile.resolve(@web_widget)
  json.widget_triggers @web_widget.inbox.resolved_widget_triggers
  json.widget_tracking @web_widget.inbox.public_widget_tracking
  json.widget_appearance @web_widget.inbox.resolved_widget_appearance
end

json.contact do
  json.email @contact.email
  json.id @contact.id
  json.identifier @contact.identifier
  json.name @contact.name
  json.phone_number @contact.phone_number
  json.pubsub_token @contact_inbox.pubsub_token
end

json.global_config @global_config
