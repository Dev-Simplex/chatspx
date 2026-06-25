# frozen_string_literal: true

# == Schema Information
#
# Table name: funnels
#
#  id         :bigint           not null, primary key
#  color      :string
#  name       :string           not null
#  position   :integer          default(0)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  team_id    :bigint
#  inbox_ids  :jsonb            default([]), not null
#
class Funnel < ApplicationRecord
  belongs_to :account
  belongs_to :team, optional: true
  has_many :funnel_stages, dependent: :destroy
  has_many :funnel_items, dependent: :destroy
  has_many :funnel_custom_fields, dependent: :destroy
  has_many :funnel_views, dependent: :destroy
  has_many :funnel_automations, dependent: :destroy
  has_many :funnel_metric_snapshots, dependent: :destroy

  # Kanban v2 (Fase 1): funnel-level config persisted in the `settings` jsonb
  # (e.g. default view, deadline_mode toggle). JSONB default {} — additive.
  # Fase 8 adds public WorkForm config: form_enabled, form_token (public,
  # unguessable), form_inbox_id (Channel::Api inbox to create the conversation in),
  # form_title.
  store_accessor :settings, :deadline_mode, :default_view, :card_field_visibility,
                 :form_enabled, :form_token, :form_inbox_id, :form_title

  validates :name, presence: true
  validates :name, length: { minimum: 1 }, allow_blank: false
  validates :account_id, presence: true

  before_save :normalize_inbox_ids

  scope :ordered, -> { order(:position, :created_at) }

  # Fase 8: locate a funnel by its public form token (constant-ish lookup).
  def self.for_form_token(token)
    return if token.blank?

    where("settings ->> 'form_token' = ?", token.to_s).first
  end

  # Generate the public form token on first enable; idempotent thereafter.
  def ensure_form_token!
    return form_token if form_token.present?

    update!(form_token: SecureRandom.hex(24))
    form_token
  end

  def public_form_enabled?
    ActiveModel::Type::Boolean.new.cast(form_enabled) && form_token.present?
  end
  scope :for_inbox, ->(inbox_id) { where("inbox_ids = '[]' OR inbox_ids @> ?", [inbox_id].to_json) }

  def stages_ordered
    funnel_stages.ordered
  end

  def allows_inbox?(inbox_id)
    return true if inbox_ids.blank? || inbox_ids.empty?

    inbox_ids.include?(inbox_id.to_i)
  end

  def allowed_inboxes
    all_inboxes = Inbox.where(account_id: account_id)
    return all_inboxes if inbox_ids.blank? || inbox_ids.empty?

    all_inboxes.where(id: inbox_ids)
  end

  private

  def normalize_inbox_ids
    self.inbox_ids = [] if inbox_ids.nil?
    self.inbox_ids = inbox_ids.compact.map(&:to_i) if inbox_ids.is_a?(Array)
  end
end
