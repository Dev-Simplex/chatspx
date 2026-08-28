# frozen_string_literal: true

# Quem SUPERVISIONA time não administra a PLATAFORMA. Fonte única da regra —
# espelha o formato de TeamSupervision/AgentMessageIsolation (module_function,
# viewer-dependent, consultado em cada ponto em vez de virar association).
#
# O recorte é deliberadamente curto. Só estes seis itens saem do alcance do
# supervisor: Console de Super Admin, Atributos personalizados, Robôs, Macros,
# Integrações e Fluxo de conversa. Tudo o mais que ele já acessava — caixas de
# entrada, agentes, times, etiquetas, respostas prontas, automações, relatórios,
# campanhas, SLA, auditoria, conexões WAHA — continua igual.
#
# LER NÃO É ADMINISTRAR: os pontos de leitura que alimentam a tela de atendimento
# ficam abertos de propósito (definições de atributo no painel do contato, macro
# executada dentro da conversa, agent_bots#index na tela da caixa, integrations/
# apps#index que o botão de vídeo do Dyte e a sugestão de etiqueta do OpenAI
# consultam). Fechar esses é quebrar a tela do supervisor, não protegê-la.
#
# Inerte quando ninguém supervisiona nada: TeamSupervision devolve [] numa consulta
# indexada e todo caller faz short-circuit. Sem User (job/webhook/API pública)
# nunca restringe.
module SupervisorSettingsScope
  module_function

  # true quando o usuário é supervisor de time NESTA conta e, por isso, perde as
  # configurações de plataforma.
  def blocked?(user, account)
    TeamSupervision.supervisor?(user, account)
  end

  # O Console de Super Admin é da INSTALAÇÃO, não de uma conta — então aqui a
  # pergunta é "supervisiona algum time em qualquer conta?". Esconder o item do
  # menu não tira o acesso: /super_admin é um escopo Devise próprio e quem tem
  # users.type = 'SuperAdmin' entra pela URL. Esta é a guarda que fecha a URL.
  def blocked_from_console?(user)
    return false unless user.is_a?(User)

    TeamSupervisor.exists?(user_id: user.id) || AccountUser.exists?(user_id: user.id, supervisor: true)
  end
end
