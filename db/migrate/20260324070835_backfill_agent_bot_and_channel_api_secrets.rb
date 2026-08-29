# Registro antigo nasceu antes da coluna existir e ficaria com `secret` NULL para sempre —
# e webhook sem segredo sai sem assinatura, que e exatamente o buraco que o bloco 4.13
# fecha. O backfill so toca quem esta NULL: quem ja tem segredo combinado com o destino
# nao pode te-lo trocado por baixo, senao a proxima entrega passa a falhar a verificacao
# do outro lado.
#
# `reset_column_information` de proposito: numa instalacao nova estas tres migrations
# rodam na mesma execucao, e a classe pode ja ter sido carregada com o cache de colunas de
# ANTES do `add_column` — o `update` ignoraria a coluna em silencio.
#
# `validate: false` porque uma linha legada que nao passa numa validacao nova (o AgentBot
# ganhou validacoes proprias depois) nao pode abortar a migration inteira e deixar metade
# da frota sem segredo.
class BackfillAgentBotAndChannelApiSecrets < ActiveRecord::Migration[7.1]
  def up
    AgentBot.reset_column_information
    Channel::Api.reset_column_information

    [AgentBot, Channel::Api].each do |model|
      model.where(secret: nil).find_each do |record|
        record.secret = SecureRandom.urlsafe_base64(24)
        record.save!(validate: false)
      end
    end
  end

  def down
    # no-op: a remocao da coluna nas migrations anteriores ja limpa tudo
  end
end
