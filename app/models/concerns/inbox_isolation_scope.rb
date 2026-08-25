# frozen_string_literal: true

# Escopo POR TIME das 3 regras de isolamento da caixa de entrada. Extraido do Inbox para a regra
# ter um arquivo proprio — ela e consultada por ~10 pontos (association de mensagens, finder de
# conversas, preloader da lista, busca, servicos de isolamento, guard de acesso, download em massa,
# galeria de anexos, job de acoes em massa) e reescreve-la em qualquer um deles e como uma delas
# passa a esconder o que deveria aparecer.
module InboxIsolationScope
  extend ActiveSupport::Concern

  included do
  # ESCOPO POR TIME DAS 3 REGRAS DE ISOLAMENTO — a regra mora AQUI e so aqui.
    # A flag booleana LIGA a regra na caixa; a lista de times diz EM QUAIS times ela vale.
    # Chave = a coluna booleana, valor = a coluna com a lista de times.
    ISOLATION_RULES = {
      team_message_isolation: :team_message_isolation_team_ids,
      agent_message_isolation: :agent_message_isolation_team_ids,
      agent_conversation_isolation: :agent_conversation_isolation_team_ids
    }.freeze

    # Regras em que conversa SEM time NAO e isolada. Vale so para as duas de MENSAGEM: a
    # conversa nasce sem time, antes da triagem, e esconder as bolhas dela esconderia o lead
    # novo de quem precisa atender.
    #
    # `agent_conversation_isolation` fica DE FORA de proposito. Ali o criterio de fechamento
    # nao e o time, e sim "esta atribuida a outra pessoa" — hoje, com a flag ligada, a conversa
    # de um colega e bloqueada tenha ela time ou nao. Se o escopo por time abrisse a conversa
    # sem time, o deploy desta feature ABRIRIA para todo agente a conversa atribuida ao colega
    # que ainda nao passou pela triagem: regressao de seguranca, nao relaxamento pedido.
    # Principio: o escopo por time so pode RELAXAR a regra nos times que o admin excluiu —
    # nunca abrir o que hoje esta fechado por um criterio que nao e o time.
    TEAMLESS_EXEMPT_RULES = %i[team_message_isolation agent_message_isolation].freeze

    # "Esta caixa isola ESTE time por ESTA regra?" — pergunta unica de todos os pontos de
    # aplicacao. Saidas para FALSE, todas errando para o lado de MOSTRAR:
    #
    #   1. flag desligada           -> a regra nem existe na caixa;
    #   2. conversa SEM time        -> nao isolada, SO nas regras de mensagem (ver acima);
    #   3. time fora da lista       -> o admin escolheu outros times.
    #
    # Lista VAZIA = vale para TODOS os times = o comportamento historico. E o que garante
    # que nenhuma caixa ja configurada mude de comportamento no deploy desta feature.
    #
    # `fetch` de proposito: regra desconhecida estoura KeyError em vez de virar "nao isola"
    # em silencio — errar para "mostrar" e a preferencia, mas nunca por digitacao errada.
    def isolation_applies_to_team?(rule, team_id)
      key = rule.to_sym
      column = ISOLATION_RULES.fetch(key) # regra desconhecida estoura, nao vira "nao isola"
      return false unless self[key]
      return false if team_id.blank? && TEAMLESS_EXEMPT_RULES.include?(key)

      ids = Array(self[column]).compact.map(&:to_i)
      return true if ids.empty?
      # Conversa SEM time numa regra NAO isenta (agent_conversation_isolation): a regra continua
      # valendo mesmo com lista preenchida. "Sem time" nao e um time que o admin excluiu — se
      # escolher "so Vendas" abrisse as conversas sem time, restringir o escopo AFROUXARIA o
      # acesso, que e o oposto do que a tela promete.
      return true if team_id.blank?

      ids.include?(team_id.to_i)
    end

    # MESMA regra de `isolation_applies_to_team?`, porem como fragmento SQL, para os pontos
    # de leitura que montam SQL cru (conversation_finder, list_preloader, search_service,
    # agent_conversation_isolation). Existe para a regra nao ser reescrita em 4 dialetos
    # ligeiramente diferentes — que e exatamente como uma delas passa a esconder o que
    # deveria aparecer. Os apelidos sao das tabelas ja unidas na query do chamador.
    #
    # O `COALESCE(array_length(...), 0) = 0` e o caso da lista vazia: array_length de array
    # vazio devolve NULL em PG, e sem o COALESCE a comparacao viraria NULL — ou seja, o caso
    # retrocompativel (o mais comum!) cairia para o lado de ESCONDER.
    # Nome da regra e da coluna saem da whitelist congelada acima: nao ha interpolacao de
    # entrada do usuario aqui.
    def self.isolation_applies_sql(rule, inbox_alias: 'inboxes', conversation_alias: 'conversations')
      key = rule.to_sym
      list = "#{inbox_alias}.#{ISOLATION_RULES.fetch(key)}"
      vazia = "COALESCE(array_length(#{list}, 1), 0) = 0"
      casa = "#{conversation_alias}.team_id = ANY(#{list})"
      # COALESCE na FLAG: `inboxes.team_message_isolation` e a unica das tres que ficou NULLABLE
      # no schema. Sem o COALESCE, `flag = true` com a coluna NULL devolve NULL, e um `NOT (...)`
      # no chamador tambem devolve NULL — a linha sumiria em silencio. O Ruby ja trata NULL como
      # false (`unless self[key]`); aqui o SQL passa a concordar. Com isto o fragmento NUNCA
      # devolve NULL, entao negar o resultado no chamador e seguro.
      # Espelha `isolation_applies_to_team?`: a isencao do time NULO vale so nas regras de
      # MENSAGEM (TEAMLESS_EXEMPT_RULES). Em agent_conversation_isolation a conversa sem time
      # continua alcancada pela regra — abrir ali seria regressao de seguranca, nao escopo.
      escopo = if TEAMLESS_EXEMPT_RULES.include?(key)
                 "#{conversation_alias}.team_id IS NOT NULL AND (#{vazia} OR #{casa})"
               else
                 # Sem time SEMPRE alcancado aqui (ver o `return true if team_id.blank?` acima):
                 # restringir o escopo nao pode afrouxar o acesso.
                 "(#{conversation_alias}.team_id IS NULL OR #{vazia} OR #{casa})"
               end
      "(COALESCE(#{inbox_alias}.#{key}, FALSE) AND #{escopo})"
    end
  end
end
