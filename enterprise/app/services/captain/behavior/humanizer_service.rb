class Captain::Behavior::HumanizerService
  def initialize(config:)
    @config = config || {}
    @max_chars = (@config['max_chars'] || 300).to_i
  end

  def split(text)
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
