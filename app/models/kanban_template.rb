# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_templates
#
#  id                 :bigint           not null, primary key
#  slug               :string           not null
#  name               :string           not null
#  description        :string
#  vertical           :string
#  icon               :string
#  color              :string
#  locale             :string           default("pt-BR"), not null
#  version            :integer          default(1), not null
#  stages_config      :jsonb            default([]), not null
#  sample_cards       :jsonb            default([]), not null
#  automations_config :jsonb            default([]), not null
#  is_official        :boolean          default(true), not null
#  account_id         :bigint
#
class KanbanTemplate < ApplicationRecord
  belongs_to :account, optional: true

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  scope :official,   -> { where(is_official: true) }
  scope :for_locale, ->(locale) { where(locale: locale) }
  scope :ordered,    -> { order(:vertical, :name) }
end
