# frozen_string_literal: true

# Bloco 4.02 (BK-22) — os limites de uma mensagem ESTRUTURADA dependem do CANAL, e ate aqui so
# existiam os da Meta. `Flows::InteractiveAction` truncava TODO titulo em 24 caracteres, inclusive
# no chat de site, onde nenhuma regra da Meta vale: "Falar com o time financeiro" chegava ao
# visitante como "Falar com o time financ". O mesmo Flow passa a renderizar adequadamente nos dois
# canais — que e o aceite do BK-22.
#
# O QUE NAO MUDA ENTRE CANAIS, de proposito: `value`. Ele e o id da resposta e o `edge.branch` que
# o `wait_for_reply` casa. Se o corte de `value` divergisse por canal, o MESMO fluxo ramificaria
# diferente no WhatsApp e no site — o pior tipo de defeito, porque so aparece num dos dois.
module Flows::StructuredMessageLimits
  # Limites OFICIAIS da Meta (linha de lista max 24, botao max 20 — o front cuida do 20; id da
  # reply max 200; description so aparece em lista; body 1024). Sao os que ja valiam.
  META = { items: 10, title: 24, value: 200, description: 72, body: 1024 }.freeze

  # Chat de site. Cada numero tem procedencia, nao e chute:
  #  · body 10_000     — e o limite que o proprio produto declara para mensagem de canal generico
  #                      (`MESSAGE_MAX_LENGTH.GENERAL`, shared/helpers/MessageTypeHelper.js);
  #  · title/description 160 — o mesmo teto de rotulo curto que o pre-chat ja usa
  #                      (`Channel::WebWidget::PreChatFormSchema::MAX_TEXT_LENGTH`);
  #  · items 20        — NAO e limite do canal (o widget desenha um <ul>, sem teto proprio): e
  #                      guarda contra lista patologica, com folga de 2x sobre o teto da Meta;
  #  · value 200       — IGUAL ao da Meta, pelo motivo do cabecalho.
  WEB = { items: 20, title: 160, value: 200, description: 160, body: 10_000 }.freeze

  # `for` porque e exatamente isso que se le no ponto de uso: os limites PARA esta conversa.
  def self.for(conversation)
    conversation&.inbox&.web_widget? ? WEB : META
  end
end
