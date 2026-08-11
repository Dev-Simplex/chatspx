class AddDispatchAssigneeToCampaigns < ActiveRecord::Migration[7.1]
  # Dono do disparo: quem atende as respostas DESTA campanha. Opcional — sem ele o
  # comportamento segue o de antes (conversa fecha com o time e SEM agente, e o
  # reply reabre pra fila do time).
  #
  # Existe porque "conversa sem dono dentro de um time" ja falhou nesta base: o
  # Chatwoot so liga a notificacao de atribuicao de fabrica (`conversation_assignment`),
  # nao a de mensagem nova em conversa atribuida — entao fila de time depende de
  # alguem lembrar de olhar. Foi o diagnostico do "ninguem viu" com 432 leads
  # parados +12h. "Quem atende esta campanha" e dado DA CAMPANHA, nao config da conta.
  #
  # ATENCAO (limite deliberado): so use em inbox SEM IA. Atribuir um humano dispara
  # o `reset_agent_bot_when_assignee_present` e CALA o agente da conversa. Campanha
  # em inbox com IA precisa DESIGNAR sem atribuir (frente spx/rodizio) — o campo
  # certo la sera outro, nao este.
  def change
    add_column :campaigns, :dispatch_assignee_id, :bigint
    add_index :campaigns, :dispatch_assignee_id
  end
end
