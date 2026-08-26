# Herança de leitura entre respostas ao MESMO story do Instagram.
#
# Cada pessoa que responde a um story gera um anexo NOVO com o arquivo baixado de novo —
# byte a byte idêntico (mesmo checksum do blob), registro diferente. Como o cache da leitura
# vive no `meta` do anexo, sem isto o mesmo vídeo iria para a visão e para o Whisper uma vez
# por pessoa. Medido na conta 7 (inbox 57), 30 dias: 865 respostas para 479 stories, um deles
# respondido 20 vezes — 384 leituras redundantes, 44% do total.
#
# A busca é pelo `meta` do próprio anexo, que é jsonb SIMPLES. NÃO pelo `content_attributes`
# da mensagem: aquele é `store coder: JSON` sobre jsonb (dupla serialização), e um `->>`
# ingênuo casaria com zero linhas em silêncio — armadilha que já mordeu o NPS e o eval.
class Captain::MediaStoryCache
  META_STORY_KEY = 'story_id'.freeze

  def initialize(attachment:)
    @attachment = attachment
  end

  # Só existe em resposta a story. Vídeo comum não tem irmão e é sempre lido uma vez.
  def story_id
    return @story_id if defined?(@story_id)

    @story_id = (attachment.message&.content_attributes || {})[META_STORY_KEY].to_s.strip.presence
  end

  # Texto que outro anexo do mesmo story já produziu para esta chave, ou nil.
  def leitura_irma(chave)
    return nil if story_id.blank?

    irmao = irmaos.where('meta ->> :k IS NOT NULL', k: chave).order(created_at: :desc).first
    texto = irmao&.meta&.[](chave).to_s.strip.presence
    return nil if texto.blank?

    Rails.logger.info("[MediaStoryCache] #{chave} herdada do anexo #{irmao.id} (story #{story_id}) att=#{attachment.id}")
    texto
  end

  private

  attr_reader :attachment

  def irmaos
    Attachment.where(account_id: attachment.account_id)
              .where.not(id: attachment.id)
              .where('meta ->> :s = :sid', s: META_STORY_KEY, sid: story_id)
  end
end
