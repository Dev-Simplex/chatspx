# Os templates HSM que o canal de uma inbox já sincronizou da Meta, lidos com a mesma
# lente do envio.
#
# Existe porque configurar a abertura à mão é o caminho curto para o erro #132000: quando
# os parâmetros que a engine monta não batem com o template aprovado, a Meta recusa a
# mensagem, o lead entra MUDO e o único rastro é uma linha de log. Para recusar essa
# combinação antes de salvar é preciso saber o que o template aprovado exige — e quem
# responde isso é o canal, não um campo de texto.
#
# Espelha `Whatsapp::TemplateProcessorService#find_template`: só vale o template APROVADO,
# casado por nome + idioma sem diferenciar maiúsculas. Template pendente ou rejeitado está
# no canal e não envia — por isso não entra na lista.
#
# Só lê. Agnóstico: nada aqui conhece cliente, campanha ou nome de template.
class LeadCampaigns::TemplateCatalog
  # `{{1}}` (posicional) ou `{{nome}}` (nomeado) — a Meta aceita as duas formas.
  VARIAVEL = /\{\{\s*([^}]+?)\s*\}\}/
  FORMATOS_DE_MIDIA = %w[IMAGE VIDEO DOCUMENT].freeze
  APROVADO = 'approved'.freeze

  def initialize(inbox)
    @inbox = inbox
  end

  # `false` quando o canal nem guarda templates (web widget, WAHA): não dá para afirmar
  # nada sobre o que está configurado, e a tela precisa dizer isso em vez de acusar.
  def disponivel?
    lista.is_a?(Array)
  end

  def aprovados
    @aprovados ||= (disponivel? ? lista : []).filter_map { |bruto| descrever(bruto) if aprovado?(bruto) }
  end

  # Sem idioma, casa pelo nome — e só devolve quando a resposta é única. Nome aprovado em
  # dois idiomas é ambíguo de propósito: quem escolhe o idioma é quem configura, porque a
  # Meta trata (nome, idioma) como templates diferentes.
  def encontrar(nome, idioma = nil)
    candidatos = aprovados.select { |descritor| descritor[:nome] == nome.to_s.strip }
    return candidatos.first if idioma.blank? && candidatos.one?
    return nil if idioma.blank?

    candidatos.find { |descritor| descritor[:idioma].to_s.casecmp?(idioma.to_s.strip) }
  end

  def ambiguo?(nome)
    aprovados.count { |descritor| descritor[:nome] == nome.to_s.strip } > 1
  end

  def nomes
    aprovados.map { |descritor| descritor[:nome] }.uniq
  end

  private

  def lista
    return @lista if defined?(@lista)

    # `try`: só o canal WhatsApp guarda templates sincronizados; os demais não respondem.
    @lista = @inbox&.channel.try(:message_templates)
  rescue StandardError
    @lista = nil
  end

  def aprovado?(bruto)
    bruto.is_a?(Hash) && bruto['name'].present? && bruto['status'].to_s.casecmp?(APROVADO)
  end

  def descrever(bruto)
    corpo = componente(bruto, 'BODY')
    cabecalho = componente(bruto, 'HEADER')
    variaveis = variaveis_de(corpo&.dig('text'))
    {
      nome: bruto['name'].to_s,
      idioma: bruto['language'].to_s,
      categoria: bruto['category'].to_s,
      corpo: corpo&.dig('text').to_s,
      variaveis: variaveis,
      impedimento: impedimento(bruto, cabecalho, variaveis)
    }
  end

  # Por que a engine de captação NÃO consegue enviar este template. A abertura do lead manda
  # só os parâmetros do CORPO (`create_initial_template_message`): qualquer outra coisa que o
  # template exija chega vazia e a Meta recusa o envio inteiro. Devolve um símbolo — a
  # tradução mora em `config/locales`, para a tela dizer o porquê em vez de só sumir com a
  # opção. `nil` = a engine dá conta.
  def impedimento(bruto, cabecalho, variaveis)
    return :cabecalho_de_midia if FORMATOS_DE_MIDIA.include?(cabecalho&.dig('format').to_s.upcase)
    return :cabecalho_com_variavel if variaveis_de(cabecalho&.dig('text')).any?
    return :botao_com_variavel if botao_com_variavel?(bruto)
    # A engine numera os parâmetros do corpo (`{'1' => ..., '2' => ...}`); template de
    # parâmetro NOMEADO espera a chave com o nome da variável e recusa a numeração.
    return :parametro_nomeado if variaveis.any? && nomeado?(bruto, variaveis)

    nil
  end

  def nomeado?(bruto, variaveis)
    bruto['parameter_format'].to_s.casecmp?('NAMED') || variaveis.any? { |token| !token.match?(/\A\d+\z/) }
  end

  def botao_com_variavel?(bruto)
    botoes(bruto).any? { |botao| botao.is_a?(Hash) && variaveis_de(botao['url']).any? }
  end

  def botoes(bruto)
    componentes(bruto).select { |item| item['type'].to_s.casecmp?('BUTTONS') }
                      .flat_map { |item| item['buttons'].is_a?(Array) ? item['buttons'] : [] }
  end

  def componente(bruto, tipo)
    componentes(bruto).find { |item| item['type'].to_s.casecmp?(tipo) }
  end

  def componentes(bruto)
    lista = bruto['components']
    lista.is_a?(Array) ? lista.select { |item| item.is_a?(Hash) } : []
  end

  # Na ordem em que aparecem e sem repetir: `{{1}} ... {{1}}` é UM parâmetro para a Meta.
  def variaveis_de(texto)
    texto.to_s.scan(VARIAVEL).flatten.map(&:strip).reject(&:blank?).uniq
  end
end
