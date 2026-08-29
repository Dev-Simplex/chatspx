# Bloco 4.13 — a rotacao devolve o segredo NOVO uma vez. Sem `expose_secret` a resposta
# viria com `has_secret: true` e nada mais: o cliente teria trocado a chave e ficado sem
# saber qual e, o que quebraria a assinatura no destino sem nenhuma forma de conserto.
json.partial! 'api/v1/models/agent_bot', formats: [:json], resource: AgentBotPresenter.new(@agent_bot), expose_secret: true
