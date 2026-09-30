# Guarda de saída para telefone (CHAT-159): a IA não escreve telefone em texto. Caso real
# (conta 6, conv 42863): o cliente pediu o WhatsApp e a IA respondeu duas vezes um número que não
# existia em lugar nenhum. Regra de prompt é conduta, não trava.
#
# Telefone da empresa sai pelo card de contato (ferramenta `enviar_contato_unidade`), nunca
# digitado pelo modelo: cadastro de unidade, config do assistente e retorno de ferramenta NÃO
# autorizam o número em texto, porque o caminho certo para eles é o card.
#
# A única fonte que libera um número no texto é alguém de carne e osso tê-lo escrito nesta
# conversa: o cliente (a IA confirmando o número que ele passou) ou um humano da equipe. O que a
# própria IA disse antes não conta — senão o número inventado num turno se legitimaria no seguinte,
# que foi exatamente o que aconteceu naquela conversa.
#
# Ligada para todas as contas. Chave de emergência para desligar, por assistente
# (`behavior.guards.telefone_sem_fonte = false`) ou por conta
# (`custom_attributes.captain_guard_telefone_sem_fonte = false`).
class Captain::Behavior::PhoneSourceGuard
  # Telefone brasileiro na resposta: DDI e DDD opcionais, com ou sem o nono dígito, com ou sem
  # separadores. Exige dois blocos de 4 dígitos, o que deixa de fora preço, CEP, CPF e código.
  TELEFONE = /(?<!\d)(?:\+?55[\s.-]?)?(?:\(\s?\d{2}\s?\)\s?|\d{2}[\s.-]?)?(?:9[\s.-]?)?\d{4}[\s.-]?\d{4}(?!\d)/
  # Comparação pelos 8 últimos dígitos: absorve DDI, DDD e o nono dígito, que a IA e o cliente
  # escrevem cada um de um jeito.
  CHAVE = 8
  REMETENTES_DA_IA = %w[Captain::Assistant AgentBot].freeze

  def self.enabled_for?(assistant)
    chaves = [
      (assistant&.behavior || {}).dig('guards', 'telefone_sem_fonte'),
      assistant&.account&.custom_attributes&.dig('captain_guard_telefone_sem_fonte')
    ]
    chaves.none? { |valor| ActiveModel::Type::Boolean.new.cast(valor) == false }
  end

  def initialize(conversation:)
    @conversation = conversation
  end

  # Telefones da resposta que ninguém de carne e osso escreveu na conversa, como a IA os escreveu.
  def sem_fonte(content)
    citados = content.to_s.scan(TELEFONE).map(&:strip).uniq
    return [] if citados.empty?

    conhecidas = chaves_das_fontes
    citados.reject { |numero| conhecidas.include?(chave(numero)) }
  end

  # Tira do texto as frases que citam os números sem fonte. Frase inteira, não só os dígitos:
  # sobrar "nosso WhatsApp é , pode chamar" é uma promessa quebrada, pior que não dizer nada.
  def remover(content, numeros)
    linhas = content.to_s.each_line.map do |linha|
      linha.chomp.split(/(?<=[.!?])\s+/).reject { |frase| numeros.any? { |numero| frase.include?(numero) } }.join(' ')
    end
    linhas.join("\n").gsub(/\n{3,}/, "\n\n").strip
  end

  private

  def chave(numero)
    numero.to_s.gsub(/\D/, '').last(CHAVE)
  end

  def chaves_das_fontes
    @conversation.messages.where(private: false)
                 .where('messages.sender_type IS NULL OR messages.sender_type NOT IN (?)', REMETENTES_DA_IA)
                 .pluck(:content)
                 .flat_map { |texto| texto.to_s.scan(TELEFONE) }
                 .map { |numero| chave(numero) }
                 .select { |c| c.length == CHAVE }
                 .to_set
  end
end
