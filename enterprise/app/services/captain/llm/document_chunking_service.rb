# Divide o conteúdo de um documento em chunks (passagens) para embedding/RAG.
# Recursivo por fronteiras semânticas: parágrafo -> frase -> hard-split. Com overlap.
# Ruby puro, sem dependência externa.
class Captain::Llm::DocumentChunkingService
  DEFAULT_CHUNK_SIZE = 1000
  DEFAULT_OVERLAP = 150

  def initialize(content, chunk_size: DEFAULT_CHUNK_SIZE, overlap: DEFAULT_OVERLAP)
    @content = content.to_s.gsub("\r\n", "\n")
    @chunk_size = chunk_size
    @overlap = overlap
  end

  def chunks
    text = @content.strip
    return [] if text.empty?

    pack(split_units(text))
  end

  private

  # Quebra em unidades: parágrafos; parágrafo grande vira frases; frase gigante é hard-split.
  def split_units(text)
    text.split(/\n{2,}/).flat_map do |para|
      para = para.strip
      next [] if para.empty?

      para.length <= @chunk_size ? [para] : split_sentences(para)
    end
  end

  def split_sentences(para)
    para.scan(/[^.!?\n]+[.!?]*\s*/).map(&:strip).reject(&:empty?).flat_map do |sentence|
      sentence.length <= @chunk_size ? [sentence] : hard_split(sentence)
    end
  end

  def hard_split(str)
    str.scan(/.{1,#{@chunk_size}}/m).map(&:strip)
  end

  # Empacota unidades em chunks <= chunk_size, carregando overlap do chunk anterior.
  def pack(units)
    chunks = []
    current = +''

    units.each do |unit|
      if current.empty?
        current = unit.dup
      elsif current.length + 1 + unit.length <= @chunk_size
        current << "\n" << unit
      else
        chunks << current
        current = overlap_tail(current) + unit
      end
    end
    chunks << current unless current.strip.empty?
    chunks
  end

  def overlap_tail(text)
    return '' if @overlap <= 0

    tail = text[[-@overlap, -text.length].max..] || text
    "#{tail}\n"
  end
end
