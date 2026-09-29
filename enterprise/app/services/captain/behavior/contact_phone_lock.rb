# Trava de teste do assistente (CHAT-171): com `behavior.router.only_contact_phones` preenchido,
# a IA só atende esses telefones. Lista vazia/ausente => atende todo mundo (padrão).
#
# Ponto ÚNICO da regra: o RouterService consulta antes de responder e os caminhos que
# ATRIBUEM a IA consultam antes de entregar a conversa ao espelho — senão a conversa fica
# presa num dono que nunca vai falar.
class Captain::Behavior::ContactPhoneLock
  def initialize(assistant)
    @phones = Array((assistant.behavior || {}).dig('router', 'only_contact_phones')).compact_blank
  end

  def allows?(contact)
    return true if @phones.empty?

    allowed = @phones.flat_map { |p| phone_variations(p) }.uniq
    candidate_phones(contact).flat_map { |p| phone_variations(p) }.intersect?(allowed)
  end

  private

  # Telefones a tentar match: contact.phone_number e o JID puro do WAHA (sem @c.us).
  # O JID canônico não tem o "9 a mais" do celular brasileiro, enquanto phone_number pode
  # ter — então olhamos os dois.
  def candidate_phones(contact)
    return [] unless contact

    jid = contact.custom_attributes&.dig('waha_whatsapp_jid').to_s.split('@').first
    [contact.phone_number, jid].compact_blank
  end

  # Para números brasileiros gera variações cobrindo: com/sem DDI 55, com/sem o "9 a mais"
  # do celular pós-2012. Cobre o WAHA (que historicamente persiste JID sem o 9), o
  # phone_number do contato e operadores digitando à mão sem DDI.
  def phone_variations(value)
    digits = value.to_s.gsub(/\D/, '')
    with_ddi = brazilian_with_ddi(digits)
    return [digits] if with_ddi.nil?

    prefix = with_ddi[0, 4] # "55" + DDD
    local = with_ddi[4..]   # número local (8 ou 9 dígitos)
    local = local[1..] if local.length == 9 && local.start_with?('9')
    [with_ddi, "#{prefix}9#{local}", "#{prefix}#{local}"].uniq
  end

  # Número brasileiro normalizado com DDI 55; nil quando não parece número brasileiro.
  def brazilian_with_ddi(digits)
    return digits if digits.start_with?('55') && [12, 13].include?(digits.length)
    return "55#{digits}" if !digits.start_with?('55') && [10, 11].include?(digits.length)

    nil
  end
end
