# frozen_string_literal: true

# O vocabulário do teste A/B de fluxo (bloco 6.05).
#
# ─── POR QUE NÃO HÁ MIGRATION ────────────────────────────────────────────────────────
# `flows` já tem `version` [M20 — db/schema.rb:1206], e a variante já é uma linha em
# `flows`. O que faltava não era coluna: era **designar** o visitante a uma variante,
# **reter** essa designação, e **ler** o resultado. Duas variantes são dois fluxos que
# declaram a MESMA `experiment.key` no `trigger_config` — o mesmo jsonb onde o 4.02 já
# publica o alvo do fluxo, com o mesmo contrato de defaults.
#
# ─── A DESIGNAÇÃO NÃO É SORTEIO ──────────────────────────────────────────────────────
# `assign` é função PURA de (chave do experimento, chave do visitante). Não há
# `rand`, não há gravação e não há estado: o mesmo visitante cai na mesma variante hoje,
# amanhã e depois de o servidor reiniciar. Um sorteio por requisição faria o mesmo
# visitante ver fluxos diferentes na mesma conversa, e o relatório somaria laranja com
# banana — é o modo de falha que este bloco existe para não ter.
#
# A chave do experimento entra no hash de propósito: sem ela, um visitante azarado
# cairia na variante B de TODOS os experimentos da conta, e os testes deixariam de ser
# independentes entre si.
module Flow::AbExperiment
  # Peso de quem não declara peso. 50 e 50 é a divisão que alguém espera ao abrir um A/B
  # sem configurar nada.
  DEFAULT_WEIGHT = 50
  # Teto por variante. Peso é proporção, não orçamento — 0..100 é o que a tela mostra.
  MAX_WEIGHT = 100
  # `weight: 0` é legítimo e é um recurso: pausa a variante sem apagá-la, e o histórico
  # dela continua no relatório (aceite "publicar uma variante nova não invalida o
  # histórico da anterior").
  MIN_WEIGHT = 0

  # O que vale quando a chave NÃO vem — publicado, como o resto do `trigger_config`.
  DEFAULTS = { 'key' => nil, 'weight' => DEFAULT_WEIGHT }.freeze

  # `null` entra no proprio tipo, e nao num `oneOf` por fora: com `oneOf` o 422 traz DOIS
  # erros para um valor so ("weight: valor invalido (maximum)" mais "experiment: valor
  # invalido (null)"), e quem le a tela tem de adivinhar qual dos dois e o dele. As
  # palavras-chave de objeto (`properties`, `required`) sao ignoradas quando a instancia e
  # `null`, entao a permissividade nao vaza para o caso objeto.
  SCHEMA = {
    'type' => %w[object null],
    'properties' => {
      'key' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => 64 },
      'weight' => { 'type' => 'integer', 'minimum' => MIN_WEIGHT, 'maximum' => MAX_WEIGHT }
    },
    'additionalProperties' => false,
    'required' => ['key']
  }.freeze

  module_function

  # A chave do experimento deste fluxo, ou `nil` quando ele não participa de nenhum.
  #
  # AUSÊNCIA É O ESTADO DE TODA A FROTA HOJE, e ela significa exatamente "nada muda": o
  # fluxo é escolhido pelo desempate do 4.02, nenhum evento de A/B é emitido e o
  # relatório não o enxerga.
  def key_for(flow)
    config = config_for(flow)
    key = config['key']
    key.is_a?(String) && key.present? ? key : nil
  end

  # Peso declarado, saneado. Peso ausente, não numérico ou fora da faixa vira o default —
  # um `trigger_config` torto de uma conta não pode tirar a variante do ar em silêncio
  # nem roubar todo o tráfego.
  def weight_for(flow)
    raw = config_for(flow)['weight']
    return DEFAULT_WEIGHT unless raw.is_a?(Integer) || (raw.is_a?(String) && raw.match?(/\A\d+\z/))

    raw.to_i.clamp(MIN_WEIGHT, MAX_WEIGHT)
  end

  # As variantes de um experimento, em ordem ESTÁVEL (id ASC).
  #
  # A ordem importa porque ela é que faz a designação ser reprodutível: acrescentar uma
  # variante nova no fim não reembaralha quem já estava designado às anteriores, desde
  # que os pesos das antigas não mudem. A de menor id é o CONTROLE — foi a que já estava
  # no ar.
  def variants(flows, key)
    flows.select { |flow| key_for(flow) == key }.sort_by(&:id)
  end

  # A variante deste visitante. `nil` quando não há como designar com estabilidade.
  #
  # ─── QUANDO A CHAVE DO VISITANTE NÃO EXISTE ──────────────────────────────────────
  # Devolve `nil`, e o chamador segue com a escolha normal do 4.02 SEM emitir exposição.
  # A alternativa seria sortear — e aí o mesmo visitante veria variantes diferentes a
  # cada requisição. A assimetria de dano decide: o barato é este visitante ficar FORA do
  # experimento (o relatório perde uma linha que ele nem saberia que existia); o caro é
  # ele entrar nas duas variantes e contaminar os dois lados do número que o cliente vai
  # usar para decidir.
  def assign(variants:, visitor_key:)
    return nil if visitor_key.blank?
    return nil if variants.blank?

    key = key_for(variants.first)
    total = variants.sum { |flow| weight_for(flow) }
    # Todas as variantes com peso 0: o experimento está pausado por inteiro. Ninguém é
    # designado, e ninguém é contado — melhor que dividir por zero ou eleger a primeira.
    return nil if total <= 0

    pick(variants, bucket(key, visitor_key, total))
  end

  # O balde deste visitante dentro do total de pesos. SHA-256 e não `hash`: o `hash` do
  # Ruby é semeado por processo (`RUBY_HASH_SEED`), então dois workers designariam o
  # mesmo visitante a variantes diferentes — o defeito exato que este módulo existe para
  # não ter, e que só apareceria em produção com mais de um processo.
  def bucket(key, visitor_key, total)
    Digest::SHA256.hexdigest("#{key}:#{visitor_key}")[0, 8].to_i(16) % total
  end

  def pick(variants, bucket)
    acumulado = 0
    variants.find do |flow|
      acumulado += weight_for(flow)
      bucket < acumulado
    end
  end

  def config_for(flow)
    raw = flow.try(:trigger_config)
    return DEFAULTS unless raw.is_a?(Hash)

    experiment = raw['experiment']
    return DEFAULTS unless experiment.is_a?(Hash)

    DEFAULTS.merge(experiment.slice(*DEFAULTS.keys).compact)
  end
end
