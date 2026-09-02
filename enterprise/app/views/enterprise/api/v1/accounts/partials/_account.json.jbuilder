json.subscribed_features @account.subscribed_features
# Tem agente de IA cadastrado no painel de Agentes IA? É por CONTA: a conta que não usa
# IA não deve ver o cartão de resumo em conversa nenhuma.
json.has_ai_agents @account.captain_assistants.exists?
