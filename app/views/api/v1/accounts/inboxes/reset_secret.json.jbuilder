# Bloco 4.13 — a rota `POST /inboxes/:id/reset_secret` ja existia e ja era chamada pela
# tela; o que faltava era esta view. Sem ela a acao terminava em ActionView::MissingTemplate
# DEPOIS de ter trocado o segredo — o cliente perdia a chave antiga e nao recebia a nova.
json.partial! 'api/v1/models/inbox', formats: [:json], resource: @inbox
