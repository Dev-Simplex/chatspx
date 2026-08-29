# Bloco 4.13 — mesma regra da rotacao: o segredo de assinatura sai UMA vez, na criacao.
json.partial! 'api/v1/models/agent_bot', formats: [:json], resource: AgentBotPresenter.new(@agent_bot), expose_secret: true
