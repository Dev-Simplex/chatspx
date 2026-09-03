# frozen_string_literal: true

# O RELATÓRIO do teste A/B de fluxo (bloco 6.05).
#
# Lê `tracking_events` e mais nada. Não há contador próprio, não há tabela de resumo e não
# há segunda fonte: os três fatos que o `Flows::AbTracking` grava pelo registro do 5.03 são
# o material inteiro deste arquivo.
#
# ─── A HONESTIDADE ESTATÍSTICA É O BLOCO, NÃO UM ENFEITE ─────────────────────────────
# O aceite diz que o teste **declara quando a diferença ainda não é distinguível do acaso,
# em vez de exibir o maior número**. É a parte que um A/B mal feito sempre pula, e é a que
# custa dinheiro: com 12 visitantes de cada lado, 4 conversões contra 2 "prova" que a
# variante B é o dobro melhor — e não prova nada. Aqui:
#
#   1. cada braço precisa de amostra mínima antes de qualquer comparação;
#   2. a aproximação normal só é usada quando ela vale (sucessos e fracassos esperados ≥ 5);
#   3. abaixo disso, e sempre que |z| < 1,96, o veredito é `inconclusivo` — com o motivo
#      escrito, não com o maior número em negrito.
#
# Nenhum caminho deste arquivo devolve "a vencedora" sem que os três passem.
class Flows::AbReportService
  # 95% bilateral. É o patamar que o mercado lê como "significativo", e escrevê-lo aqui é
  # melhor que espalhar 1.96 pelo código.
  Z_95 = 1.96
  # Piso de amostra por braço. Abaixo disto nem se calcula: a aproximação normal não vale e
  # o número só serviria para enganar quem o lê.
  MIN_EXPOSURES = 30
  # Regra clássica da aproximação normal para proporções: esperados ≥ 5 dos dois lados.
  MIN_EXPECTED = 5

  def initialize(account:, experiment:, period: nil)
    @account = account
    @experiment = experiment.to_s
    @period = period
  end

  def perform
    {
      'experiment' => @experiment,
      'variants' => variantes,
      'comparisons' => comparacoes(variantes)
    }
  end

  private

  # TODA variante que declara a chave entra, inclusive a de peso 0 e a que ainda não recebeu
  # ninguém. Omitir a variante sem tráfego esconderia justamente o caso que o cliente precisa
  # ver: "publiquei e não chegou ninguém".
  def flows
    @flows ||= @account.flows
                       .where("trigger_config->'experiment'->>'key' = ?", @experiment)
                       .order(:id)
                       .to_a
  end

  def variantes
    @variantes ||= flows.map { |flow| variante(flow) }
  end

  def variante(flow)
    expostos = exposicoes[flow.id.to_s].to_i
    convertidos = conversoes[flow.id.to_s].to_i
    {
      'variant' => flow.id,
      'name' => flow.name,
      'version' => flow.version,
      'weight' => Flow::AbExperiment.weight_for(flow),
      'control' => flow.id == flows.first&.id,
      'exposures' => expostos,
      'conversions' => convertidos,
      'conversion_rate' => taxa(convertidos, expostos),
      'steps' => etapas(flow, expostos)
    }
  end

  # ─── O FUNIL ─────────────────────────────────────────────────────────────────────────
  # A ORDEM das etapas vem de `flow.definition`, não do evento. É de propósito: o evento
  # guarda só qual nó foi alcançado, então uma retomada depois de um `wait` não reinicia
  # contagem nenhuma e dois ramos diferentes não disputam o mesmo "passo 3".
  #
  # `abandoned` é a queda para a etapa ANTERIOR (a primeira compara com a exposição), que é
  # a leitura que o aceite pede: onde o visitante parou.
  def etapas(flow, expostos)
    anterior = expostos
    nos_do_fluxo(flow).filter_map do |node|
      alcancaram = passos.dig(flow.id.to_s, node['id'].to_s).to_i
      next if alcancaram.zero? && anterior.zero?

      linha = {
        'node_id' => node['id'],
        'label' => node['label'].presence || node['action_name'] || node['type'],
        'reached' => alcancaram,
        'abandoned' => [anterior - alcancaram, 0].max,
        'reach_rate' => taxa(alcancaram, expostos)
      }
      anterior = alcancaram
      linha
    end
  end

  def nos_do_fluxo(flow)
    definicao = flow.definition.is_a?(Hash) ? flow.definition : {}
    Array(definicao['nodes']).select { |node| node.is_a?(Hash) && node['id'].present? }
  end

  # ─── AS COMPARAÇÕES ──────────────────────────────────────────────────────────────────
  # Cada variante é comparada com o CONTROLE (a de menor id — a que já estava no ar), e
  # nunca todas contra todas: comparação múltipla infla a chance de achar diferença onde
  # não há, e este arquivo existe para não fazer isso.
  def comparacoes(lista)
    controle = lista.first
    return [] if controle.blank?

    lista.drop(1).map { |variante| comparar(controle, variante) }
  end

  def comparar(controle, variante)
    veredito = julgar(controle, variante)
    {
      'base' => controle['variant'],
      'target' => variante['variant'],
      'base_rate' => controle['conversion_rate'],
      'target_rate' => variante['conversion_rate'],
      'lift' => elevacao(controle, variante)
    }.merge(veredito)
  end

  # O julgamento, e ele tem TRÊS saídas — nunca duas. `inconclusivo` não é o consolo de
  # quem perdeu: é a resposta certa enquanto o dado não sustenta outra.
  # Os nomes longos são de propósito: `x1/n1/x2/n2` é a notação do livro, e quem revisa este
  # arquivo daqui a um ano não está com o livro aberto. `base` é o controle, `alvo` é a
  # variante sendo comparada com ele.
  Amostra = Struct.new(:sucesso_base, :total_base, :sucesso_alvo, :total_alvo)

  # Duas etapas separadas de propósito: primeiro o que IMPEDE a comparação, depois o
  # veredito. Misturar as duas é como nasce o A/B que responde "B ganhou" para 12 visitantes.
  def julgar(controle, variante)
    amostra = Amostra.new(controle['conversions'], controle['exposures'],
                          variante['conversions'], variante['exposures'])

    impedimento(amostra) || veredito(amostra)
  end

  # `nil` quando NADA impede — e só então se calcula alguma coisa.
  def impedimento(amostra)
    pequena = amostra.total_base < MIN_EXPOSURES || amostra.total_alvo < MIN_EXPOSURES
    return inconclusivo('amostra_insuficiente', amostra: amostra) if pequena
    return inconclusivo('aproximacao_nao_vale', amostra: amostra) unless aproximacao_vale?(amostra)

    nil
  end

  def veredito(amostra)
    escore = estatistica_z(amostra)
    return inconclusivo('diferenca_dentro_do_acaso', escore: escore, amostra: amostra) if escore.abs < Z_95

    {
      'verdict' => escore.positive? ? 'pior_que_o_controle' : 'melhor_que_o_controle',
      'z' => escore.round(3),
      'p_value' => p_valor(escore),
      'confidence' => 0.95,
      'reason' => nil
    }
  end

  def inconclusivo(motivo, amostra:, escore: nil)
    {
      'verdict' => 'inconclusivo',
      'z' => escore&.round(3),
      'p_value' => escore && p_valor(escore),
      'confidence' => 0.95,
      'reason' => motivo,
      'min_exposures' => MIN_EXPOSURES,
      'exposures' => { 'base' => amostra.total_base, 'target' => amostra.total_alvo }
    }
  end

  # Sucessos E fracassos esperados ≥ 5 nos dois braços, sob a proporção agrupada. Sem isso a
  # curva normal não descreve a binomial e o escore seria um número bonito sobre nada.
  def aproximacao_vale?(amostra)
    proporcao = proporcao_agrupada(amostra)
    [amostra.total_base, amostra.total_alvo].all? do |total|
      (total * proporcao) >= MIN_EXPECTED && (total * (1 - proporcao)) >= MIN_EXPECTED
    end
  end

  # z de duas proporções, com variância agrupada. Sinal POSITIVO = o controle converte mais,
  # ou seja, a variante alvo é a pior — é o que `julgar` lê para escolher o veredito.
  def estatistica_z(amostra)
    taxa_base = amostra.sucesso_base.to_f / amostra.total_base
    taxa_alvo = amostra.sucesso_alvo.to_f / amostra.total_alvo
    proporcao = proporcao_agrupada(amostra)
    erro = Math.sqrt(proporcao * (1 - proporcao) * ((1.0 / amostra.total_base) + (1.0 / amostra.total_alvo)))
    return 0.0 if erro.zero?

    (taxa_base - taxa_alvo) / erro
  end

  def proporcao_agrupada(amostra)
    (amostra.sucesso_base + amostra.sucesso_alvo).to_f / (amostra.total_base + amostra.total_alvo)
  end

  # p bilateral pela normal padrão. `Math.erf` é da biblioteca padrão — não há aproximação
  # caseira aqui.
  def p_valor(escore)
    (2 * (1 - (0.5 * (1 + Math.erf(escore.abs / Math.sqrt(2)))))).round(4)
  end

  # Variação relativa da taxa. `nil` quando o controle não converteu ninguém: dividir por
  # zero para exibir "∞% melhor" é o tipo de número que faz alguém publicar a variante errada.
  def elevacao(controle, variante)
    base = controle['conversion_rate']
    return nil if base.nil? || base.zero?

    (((variante['conversion_rate'] - base) / base) * 100).round(2)
  end

  def taxa(parte, total)
    return 0.0 if total.to_i.zero?

    ((parte.to_f / total) * 100).round(2)
  end

  def exposicoes
    @exposicoes ||= contar(Flows::AbTracking::ASSIGNED)
  end

  def conversoes
    @conversoes ||= contar(Flows::AbTracking::CONVERTED)
  end

  def passos
    @passos ||= eventos(Flows::AbTracking::STEP)
                .group("properties->>'variant'", "properties->>'node_id'")
                .count
                .each_with_object({}) { |((variante, no), total), acc| (acc[variante] ||= {})[no] = total }
  end

  def contar(name)
    eventos(name).group("properties->>'variant'").count
  end

  def eventos(name)
    escopo = TrackingEvent.where(account_id: @account.id, name: name)
                          .where("properties->>'experiment' = ?", @experiment)
    @period ? escopo.for_period(@period) : escopo
  end
end
