# Etiquetas que a IA não atende (CHAT-180), configuradas POR CONTA em
# `account.custom_attributes['captain_etiquetas_sem_ia']`: vale para qualquer IA da conta.
# Conversa com uma dessas etiquetas — ou cujo CONTATO tenha uma delas — não é da IA.
# Lista vazia/ausente => nada muda (padrão).
#
# A etiqueta do contato é o que cobre o caso de origem: a portaria de um condomínio (Tozi,
# conv #22777) não é cliente em NENHUMA conversa, e uma conversa nova do mesmo contato nasce
# sem as etiquetas da anterior.
#
# Mesmo desenho do ContactPhoneLock: o RouterService consulta antes de responder e os caminhos
# que ATRIBUEM a IA consultam antes de entregar a conversa ao espelho.
class Captain::Behavior::SkipLabelsLock
  SETTING = 'captain_etiquetas_sem_ia'.freeze

  def initialize(account)
    @labels = Array(account&.custom_attributes&.dig(SETTING)).map { |label| label.to_s.strip.downcase }.compact_blank
  end

  def allows?(conversation)
    return true if @labels.empty? || conversation.nil?

    !labels_of(conversation).intersect?(@labels)
  end

  private

  def labels_of(conversation)
    (conversation.label_list + Array(conversation.contact&.label_list)).map { |label| label.to_s.downcase }
  end
end
