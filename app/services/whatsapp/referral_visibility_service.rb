# Carimba na conversa de onde ela veio quando o cliente chega por um anúncio de
# clique-para-WhatsApp (CTWA).
#
# O lead de FORMULÁRIO já era carimbado (Meta::LeadAds::CreateConversationService), porque ali
# somos nós que abrimos a conversa. O CTWA entra por outra porta — a pessoa escreve primeiro, a
# conversa nasce no pipeline de mensagem recebida — e por isso ficava invisível: medido na Tozi
# (conta 6, inbox 91), 45 dias, **167 conversas vindas de anúncio e 155 sem nenhum atributo de
# campanha**, 93%. Nem o marketing media, nem dava para rotear.
#
# O que a Meta manda no `referral` (medido, não suposto): `source_id` (id do ANÚNCIO, não da
# campanha), `source_type`, `source_url`, `headline`, `body`, `media_type`, `image_url` e
# `ctwa_clid`. **Não vem nome de campanha nem de conjunto** — isso exigiria consultar a Graph.
# Mas vem o `headline`, que é legível e identifica o criativo melhor que um id, então a
# visibilidade não depende de chamada externa nenhuma.
#
# Usa as MESMAS chaves do fluxo de formulário de propósito: o marketing não pode ter duas
# taxonomias para a mesma pergunta ("de onde veio esse atendimento?").
class Whatsapp::ReferralVisibilityService
  LABEL = 'anuncio'.freeze
  TIPO = 'Clique no anúncio'.freeze

  pattr_initialize [:message!]

  def perform
    return if referral.blank?
    return if conversation.blank?
    # Primeiro clique manda: a conversa é única por contato, e o que se quer saber é por onde
    # ela COMEÇOU. Reescrever a cada anúncio novo apagaria essa origem sem avisar ninguém.
    return if conversation.custom_attributes.to_h['meta_anuncio'].present?

    stamp
  rescue StandardError => e
    # Visibilidade nunca pode derrubar o recebimento de mensagem.
    Rails.logger.warn("[ReferralVisibility] conv=#{conversation&.id}: #{e.class}: #{e.message}")
  end

  private

  def conversation
    @conversation ||= message.conversation
  end

  def referral
    @referral ||= (message.content_attributes || {})['referral'].presence
  end

  def stamp
    attrs = {
      'meta_anuncio' => anuncio,
      'meta_anuncio_id' => referral['source_id'].to_s.strip.presence,
      'meta_origem' => origem,
      'meta_tipo' => TIPO
    }.compact
    return if attrs['meta_anuncio'].blank? && attrs['meta_anuncio_id'].blank?

    conversation.update!(custom_attributes: conversation.custom_attributes.to_h.merge(attrs))
    aplicar_label
  end

  # O `headline` é o título do anúncio e é o que o time reconhece. Sem ele, o começo do corpo
  # serve — é melhor que um id cru na tela de quem trabalha com a peça.
  def anuncio
    referral['headline'].to_s.strip.presence || referral['body'].to_s.strip[0, 80].presence
  end

  # Uma label só, e não uma por criativo: a primeira pergunta é "quanto do inbound vem de
  # anúncio?", e o detalhe por peça vive no atributo. Label por criativo viraria 17 labels.
  def aplicar_label
    conversation.account.labels.find_or_create_by!(title: LABEL)
    conversation.add_labels((conversation.label_list + [LABEL]).uniq)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end

  def origem
    url = referral['source_url'].to_s
    return 'Instagram' if url.include?('instagram.com')
    return 'Facebook' if url.include?('fb.me') || url.include?('facebook.com')

    nil
  end
end
