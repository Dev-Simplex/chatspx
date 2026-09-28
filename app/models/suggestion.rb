# == Schema Information
#
# Table name: suggestions
#
#  id         :bigint           not null, primary key
#  company    :string           not null
#  content    :text             not null
#  name       :string           not null
#  source     :integer          default("in_app"), not null
#  status     :integer          default("nova"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint
#  user_id    :bigint
#
# Caixa de sugestoes: o usuario manda uma ideia de melhoria e a Simplex le no Super Admin.
#
# `account` e `user` sao opcionais de proposito: o link publico (SUG-02) chega sem login, e uma
# conta apagada nao pode levar junto a sugestao nem travar a exclusao (licao das FKs da T07).
class Suggestion < ApplicationRecord
  MAX_MEDIA_SIZE_MB = 100
  MAX_CONTENT_LENGTH = 5000

  belongs_to :account, optional: true
  belongs_to :user, optional: true

  has_one_attached :media

  enum source: { in_app: 0, public_link: 1 }
  enum status: { nova: 0, lida: 1, planejada: 2, feita: 3 }

  validates :name, presence: true
  validates :company, presence: true
  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }
  validate :validate_media

  scope :recentes, -> { order(created_at: :desc) }

  private

  # Molde do Attachment#validate_file_size / #validate_file_type: so imagem ou video, ate 100 MB.
  # A SUG-02 reaproveita esta mesma validacao pelo link publico.
  def validate_media
    return unless media.attached?

    errors.add(:media, I18n.t('errors.suggestions.media.type')) unless media.content_type.to_s.start_with?('image/', 'video/')
    return unless media.byte_size > MAX_MEDIA_SIZE_MB.megabytes

    errors.add(:media, I18n.t('errors.suggestions.media.size', limit: MAX_MEDIA_SIZE_MB))
  end
end
