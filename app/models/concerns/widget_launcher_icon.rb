# O BYTE do icone do lancador (bloco 3.19, aceites 3 e 4).
#
# Ate aqui `launcher_icon` era um enum de string sem lugar nenhum para guardar uma imagem: o modo
# `image` era gravavel e inalcancavel — o SDK recebia `image`, nao achava `src`, e caia no balao.
# Este concern e o lugar que faltava.
#
# DUAS decisoes que valem mais que o codigo:
#
#   1. O byte vem do NOSSO dominio. `rails_storage_proxy_*` transmite o arquivo pela aplicacao, com
#      `Cache-Control: public, max-age=100 anos` (o `http_cache_forever` do proxy do ActiveStorage).
#      A rota de REDIRECT nao serve: com `ACTIVE_STORAGE_SERVICE=s3` ela devolve 302 para o bucket,
#      que e origem estranha — e o CSP do site do cliente (R18) barra a imagem sem avisar ninguem.
#
#   2. `url` NAO e campo de escrita. Quem produz o endereco e o upload; a tela manda o ARQUIVO.
#      Uma URL escrita a mao e RECUSADA com o motivo, e nao aceita-e-ignorada: chave aceita na
#      escrita e descartada na leitura e exatamente a mentira que este bloco existe para matar.
module WidgetLauncherIcon
  extend ActiveSupport::Concern

  included do
    has_one_attached :launcher_icon_image
    validate :acceptable_launcher_icon_image, if: -> { launcher_icon_image.changed? }
    validate :ensure_launcher_icon_url_is_not_handwritten
    validate :ensure_image_mode_has_an_image
  end

  # O caminho relativo do byte, na forma que o SCHEMA aceita gravar.
  def launcher_icon_image_path
    return if persisted_launcher_icon_blob.blank?

    Rails.application.routes.url_helpers.rails_storage_proxy_path(launcher_icon_image)
  end

  # O endereco que vai para o HTML do site do CLIENTE, e por isso e absoluto: o `<img>` do lancador
  # e criado no DOM da pagina dele, entao um caminho relativo apontaria para o dominio dele — 404
  # em todo visitante, sem erro em lugar nenhum. O host e o nosso, por construcao.
  def launcher_icon_image_url
    path = launcher_icon_image_path
    return if path.blank?

    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000').chomp('/')}#{path}"
  end

  private

  # `attached?` sozinho nao basta: um anexo cujo blob ainda nao foi gravado nao tem `signed_id`
  # utilizavel, e o caminho sairia apontando para lugar nenhum.
  #
  # O NOME importa: `launcher_icon_image_blob` ja e um metodo que o `has_one_attached` gera, e o
  # proprio ActiveStorage o chama com `public_send` no meio do `attach`. Redefini-lo aqui derrubou
  # 15 exemplos com "private method called" — a classe vence o modulo, e em silencio.
  def persisted_launcher_icon_blob
    return unless launcher_icon_image.attached?

    blob = launcher_icon_image.blob
    blob if blob&.persisted?
  end

  def acceptable_launcher_icon_image
    return unless launcher_icon_image.attached?

    if launcher_icon_image.byte_size.to_i > WidgetAppearanceSchema::MAX_LAUNCHER_ICON_BYTES
      errors.add(:launcher_icon_image,
                 I18n.t('errors.inbox.widget_config.launcher_icon_too_big',
                        limit: WidgetAppearanceSchema::MAX_LAUNCHER_ICON_BYTES,
                        size: launcher_icon_image.byte_size.to_i))
    end

    return if WidgetAppearanceSchema::LAUNCHER_ICON_CONTENT_TYPES.include?(launcher_icon_image.content_type)

    errors.add(:launcher_icon_image,
               I18n.t('errors.inbox.widget_config.launcher_icon_type',
                      types: WidgetAppearanceSchema::LAUNCHER_ICON_CONTENT_TYPES.join(', ')))
  end

  def ensure_launcher_icon_url_is_not_handwritten
    url = WidgetAppearanceSchema.launcher_icon_url(stored_launcher_icon)
    return if url.blank?
    return if url == launcher_icon_image_path

    errors.add(:widget_appearance, I18n.t('errors.inbox.widget_config.launcher_icon_url_read_only'))
  end

  # Modo `image` sem imagem e um lancador que o servidor ja sabe que vai degradar para o balao. Ele
  # degrada mesmo (`resolved_widget_appearance`, e o `onerror` do SDK atras disso), mas o
  # administrador que escolheu "foto" tem de ouvir isso AGORA, e nao descobrir olhando o site.
  def ensure_image_mode_has_an_image
    return unless WidgetAppearanceSchema.launcher_icon_mode(stored_launcher_icon) == 'image'
    return if launcher_icon_image.attached?
    # Uma inbox que JA estava em `image` sem imagem nao pode ficar inatualizavel por causa de uma
    # validacao que nasceu depois dela — seria "salvar a inbox parou de funcionar" sem que ninguem
    # tivesse mexido nela. O que a regra impede e ENTRAR nesse estado.
    return if launcher_icon_mode_was == 'image'

    errors.add(:widget_appearance, I18n.t('errors.inbox.widget_config.launcher_icon_missing_image'))
  end

  def stored_launcher_icon
    return unless widget_appearance.is_a?(Hash)

    widget_appearance['launcher_icon']
  end

  def launcher_icon_mode_was
    return unless persisted?

    previous = attribute_was('additional_attributes')
    appearance = previous['widget_appearance'] if previous.is_a?(Hash)
    return unless appearance.is_a?(Hash)

    WidgetAppearanceSchema.launcher_icon_mode(appearance['launcher_icon'])
  end
end
