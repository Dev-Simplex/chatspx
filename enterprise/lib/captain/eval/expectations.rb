# O vocabulário de expectativa de um caso de eval (bloco 6.02), e o juiz que o aplica.
#
# FECHADO DE PROPÓSITO. Expectativa em texto livre ("responder de forma simpática") só
# pode ser julgada por outro LLM — e aí o veredito volta a ser opinião, com custo, e o
# bloco perde a razão de existir. Aqui todo assert é binário e de custo zero.
#
# O juiz do caso é a soma de duas coisas:
#   1. estas expectativas, escritas pelo cliente;
#   2. os asserts do guardrail (Captain::GateAsserts) — as MESMAS regras que decidem se
#      a resposta sai (6.01). Um caso cuja resposta seria retida em produção reprova aqui.
module Captain::Eval::Expectations
  SUPPORTED = %w[contem nao_contem chama_ferramenta nao_chama_ferramenta faz_handoff].freeze

  module_function

  # Devolve a lista de erros de FORMA (não de veredito). Vazia = expectativa válida.
  def validate(expectativas)
    return ['precisa ser um objeto'] unless expectativas.is_a?(Hash)

    desconhecidas = expectativas.keys.map(&:to_s) - SUPPORTED
    erros = desconhecidas.map { |k| "expectativa desconhecida: #{k}" }
    erros + tipo_erros(expectativas)
  end

  # O veredito. `findings` vazio = o caso passou.
  def evaluate(expectativas, resposta:, ferramentas: [], handoff: false)
    exp = (expectativas || {}).with_indifferent_access
    texto = resposta.to_s
    chamadas = Array(ferramentas).map(&:to_s)

    contem_findings(exp, texto) + nao_contem_findings(exp, texto) +
      ferramenta_findings(exp, chamadas) + handoff_findings(exp, handoff)
  end

  def finding(categoria, porque)
    {
      'origem' => 'expectativa',
      'quem' => 'ia',
      'categoria' => categoria,
      'severidade' => 'alta',
      'message_id' => nil,
      'trecho' => nil,
      'porque' => porque
    }
  end

  def tipo_erros(expectativas)
    erros = []
    %w[contem nao_contem chama_ferramenta nao_chama_ferramenta].each do |chave|
      valor = expectativas[chave] || expectativas[chave.to_sym]
      next if valor.nil? || valor.is_a?(Array)

      erros << "#{chave} precisa ser uma lista"
    end
    erros
  end

  def contem_findings(exp, texto)
    Array(exp[:contem]).filter_map do |trecho|
      next if texto.downcase.include?(trecho.to_s.downcase)

      finding('nao_contem_o_esperado', "a resposta não contém \"#{trecho}\"")
    end
  end

  def nao_contem_findings(exp, texto)
    Array(exp[:nao_contem]).filter_map do |trecho|
      next unless texto.downcase.include?(trecho.to_s.downcase)

      finding('contem_o_proibido', "a resposta contém \"#{trecho}\", que o caso proíbe")
    end
  end

  def ferramenta_findings(exp, chamadas)
    faltando = Array(exp[:chama_ferramenta]).map(&:to_s) - chamadas
    sobrando = Array(exp[:nao_chama_ferramenta]).map(&:to_s) & chamadas

    faltando.map { |t| finding('nao_chamou_a_ferramenta', "o caso espera a ferramenta #{t}, que não foi chamada") } +
      sobrando.map { |t| finding('chamou_ferramenta_proibida', "a ferramenta #{t} foi chamada, e o caso a proíbe") }
  end

  def handoff_findings(exp, handoff)
    esperado = exp[:faz_handoff]
    return [] if esperado.nil?

    esperado = ActiveModel::Type::Boolean.new.cast(esperado)
    return [] if esperado == handoff

    return [finding('nao_fez_handoff', 'o caso espera handoff para humano, e ele não aconteceu')] if esperado

    [finding('fez_handoff_indevido', 'houve handoff para humano, e o caso não o espera')]
  end
end
