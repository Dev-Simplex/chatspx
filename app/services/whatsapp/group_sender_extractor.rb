# frozen_string_literal: true

# Separa o autor que a app `chatwoot` da WAHA injeta DENTRO do texto das mensagens
# de grupo, devolvendo o corpo limpo e o autor como dado estruturado.
#
# A WAHA monta o corpo assim (`src/apps/chatwoot/consumers/waha/base.ts` + i18n
# `whatsapp.group.message`), porque o Chatwoot nao tem onde guardar "quem falou"
# numa conversa de grupo — o `sender` da mensagem e sempre o contato-grupo:
#
#   "\u{1F465} *‎Rogerio Jose Da Silva (229480102662169@lid)*\n\nQual Wi-Fi esta?"
#
# Aqui a gente desfaz essa concatenacao: o `content` fica so com a mensagem e o
# autor vira `content_attributes['group_sender']` (contrato C2).
#
# Espelha `parseLegacyGroupContent` de
# `app/javascript/dashboard/helper/whatsappGroupHelper.js`, que faz o mesmo na
# exibicao para o historico ja gravado. Divergencia deliberada: aqui o corpo da
# mensagem NUNCA e alterado (nem para remover LID solto), so o prefixo e retirado.
class Whatsapp::GroupSenderExtractor
  # Prefixo de autor no inicio do corpo. O `(?:\n{1,2}|\z)` no fim garante duas
  # coisas: (1) mensagem so com o prefixo e sem texto (anexo puro) tambem e
  # tratada; (2) um `*` no meio do nome nao encerra a captura cedo demais.
  GROUP_PREFIX = /\A\u{1F465}\s*\*(.+?)\*(?:\n{1,2}|\z)/

  # Dominios de JID que a WAHA pode emitir para o participante.
  JID_DOMAINS = 'lid|c\.us|s\.whatsapp\.net'

  # "Nome (229480102662169@lid)" — o JID e ancorado no FIM, entao um nome que
  # contenha parenteses ("Fulano (Suporte)") continua inteiro.
  PARTICIPANT_WITH_JID = /\A(?<name>.*?)\s*\((?<jid>[^()\s]+@(?:#{JID_DOMAINS}))\)\z/o

  # "229480102662169@lid" — participante sem nome cadastrado.
  BARE_JID = /\A(?<jid>[^()\s]+@(?:#{JID_DOMAINS}))\z/o

  # Marcas de direcao (LRM/RLM/embeddings) que o WhatsApp embute nos nomes.
  # Invisiveis, mas quebram comparacao de string, ordenacao e busca.
  BIDI_MARKS = /[‎‏‪-‮⁦-⁩]/

  # Formato aceitavel para "o nome na verdade e um telefone": so digitos e
  # pontuacao de telefone. Qualquer letra descarta a hipotese.
  PHONE_SHAPED = /\A\+?[\d\s().\-]+\z/

  PHONE_DIGITS_RANGE = (10..15)

  # `content` limpo + `sender` no shape do contrato C2 (nil quando nada foi
  # identificado). `matched` diz se o prefixo da WAHA estava presente.
  Result = Struct.new(:content, :sender, :matched, keyword_init: true) do
    def matched?
      matched ? true : false
    end

    def sender?
      sender.present?
    end
  end

  def self.call(content)
    new(content).call
  end

  def initialize(content)
    @content = content
  end

  def call
    text = @content.to_s
    match = GROUP_PREFIX.match(text)
    return Result.new(content: @content, sender: nil, matched: false) if match.nil?

    Result.new(
      content: text[match.end(0)..].presence,
      sender: parse_participant(match[1]),
      matched: true
    )
  end

  private

  def parse_participant(raw)
    cleaned = raw.to_s.gsub(BIDI_MARKS, '').strip
    return nil if cleaned.blank?

    name_part, jid = split_jid(cleaned)
    sender = { 'name' => nil, 'lid' => nil, 'phone' => nil }
    assign_jid(sender, jid)
    assign_name(sender, name_part)

    sender.values.any?(&:present?) ? sender : nil
  end

  def split_jid(cleaned)
    if (match = PARTICIPANT_WITH_JID.match(cleaned))
      [match[:name], match[:jid]]
    elsif (match = BARE_JID.match(cleaned))
      [nil, match[:jid]]
    else
      [cleaned, nil]
    end
  end

  # `@lid` e o identificador tecnico; qualquer outro dominio ja e o telefone.
  def assign_jid(sender, jid)
    return if jid.blank?

    identifier, domain = jid.split('@', 2)
    digits = identifier.to_s.gsub(/\D/, '')
    return if digits.blank?

    if domain == 'lid'
      sender['lid'] = digits
    else
      sender['phone'] = digits
    end
  end

  def assign_name(sender, name_part)
    value = name_part.to_s.strip
    return if value.blank?

    digits = value.gsub(/\D/, '')
    if phone_like?(value, digits)
      sender['phone'] ||= digits
    else
      sender['name'] = value
    end
  end

  def phone_like?(value, digits)
    value.match?(PHONE_SHAPED) && PHONE_DIGITS_RANGE.cover?(digits.length)
  end
end
