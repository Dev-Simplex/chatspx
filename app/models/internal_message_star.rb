# frozen_string_literal: true

# == Schema Information
#
# Table name: internal_message_stars
#
#  id                  :bigint           not null, primary key
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  internal_message_id :bigint           not null
#  user_id             :bigint           not null
#
# Chat interno — "Mensagens favoritas": estrela de UM usuário numa mensagem (cada um tem as suas).
class InternalMessageStar < ApplicationRecord
  belongs_to :user
  belongs_to :internal_message

  validates :internal_message_id, uniqueness: { scope: :user_id }
end
