class Captain::Behavior::HumanizerService
  def initialize(config:)
    @config = config || {}
    @max_chars = (@config['max_chars'] || 300).to_i
  end

  def split(text)
    return [] if text.blank?

    # Cada parágrafo (separado por linha em branco) vira uma mensagem própria,
    # pra ficar picado como conversa de WhatsApp. Parágrafo acima do limite é
    # quebrado por frase.
    text.split(/\n{2,}/).flat_map { |paragraph| split_by_length(paragraph.strip) }.reject(&:blank?)
  end

  private

  def split_by_length(text)
    return [text] if text.blank? || text.length <= @max_chars

    sentences = text.split(/(?<=[.!?])\s+/)
    chunks = []
    current_chunk = +''

    sentences.each do |sentence|
      if current_chunk.empty?
        current_chunk << sentence
      elsif (current_chunk.length + sentence.length + 1) <= @max_chars
        current_chunk << ' ' << sentence
      else
        chunks << current_chunk
        current_chunk = +sentence
      end
    end

    chunks << current_chunk unless current_chunk.empty?
    chunks
  end
end
