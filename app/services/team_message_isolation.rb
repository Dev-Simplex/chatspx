# frozen_string_literal: true

# Centraliza a regra de ISOLAMENTO DE MENSAGENS POR TIME (flag team_message_isolation por
# inbox). Historicamente ela morava inteira na association `conversation.messages` porque
# dependia SÓ da conversa: com a flag ON e a conversa num time, aparecem as mensagens sem
# time (públicas) mais as do time atual, para qualquer um que olhe.
#
# A exceção por agente quebra esse "para qualquer um": agora a regra depende de QUEM olha,
# igual ao AgentMessageIsolation. Como o filtro precisa continuar dentro da association
# (é ela que todo mundo consome), o viewer entra por `Current.user` — e a GUARDA é o ponto
# inteiro deste módulo: **sem `Current.user` o filtro é MANTIDO**. Job de relatório, API
# pública e widget rodam sem viewer; tratá-los como isentos faria um job passar a enxergar
# mensagem de outro time, que é justo o acidente que a task existe para evitar.
#
# Administrador NÃO é isento aqui, e isso é o comportamento de hoje preservado de
# propósito: diferente do isolamento por agente, o filtro por time sempre valeu para todo
# mundo, e a saída do admin sempre foi desligar a flag da caixa. Mudar isso agora seria
# ampliar visibilidade sem ninguém pedir.
module TeamMessageIsolation
  ISOLATION_TYPE = 'team_message'

  module_function

  # true quando as mensagens desta conversa DEVEM ser filtradas por time para este viewer.
  #
  # Dois eixos, os dois obrigatorios: o ALCANCE por time
  # (`Inbox#isolation_applies_to_team?` = flag ON + conversa COM time + time dentro da
  # lista escolhida na caixa; lista vazia = todos os times = comportamento historico) e a
  # ISENCAO por agente. Isola se alcanca E o viewer nao e excecao.
  def apply?(conversation, user)
    return false if conversation.nil?
    return false unless conversation.inbox&.isolation_applies_to_team?(:team_message_isolation, conversation.team_id)

    !exempt?(user, conversation.inbox)
  end

  # true quando o usuário é EXCEÇÃO do isolamento por time NESTA caixa. false sem User:
  # é a guarda de job/API pública/widget descrita acima.
  def exempt?(user, inbox)
    return false unless user.is_a?(User)
    return false if inbox.blank?

    user.isolation_exempt_inbox_ids_for(inbox.account_id, ISOLATION_TYPE).include?(inbox.id)
  end
end
