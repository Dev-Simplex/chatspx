# == Schema Information
#
# Table name: campaign_recipients
#
#  id              :bigint           not null, primary key
#  canonical_phone :string
#  delivered_at    :datetime
#  external_error  :string
#  failed_at       :datetime
#  name            :string
#  phone_number    :string           not null
#  pricing         :jsonb            not null
#  read_at         :datetime
#  replied_at      :datetime
#  sent_at         :datetime
#  status          :integer          default("pending"), not null
#  template_params :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  campaign_id     :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint
#  message_id      :bigint
#
# Indexes
#
#  index_campaign_recipients_on_account_id_and_canonical_phone  (account_id,canonical_phone)
#  index_campaign_recipients_on_account_id_and_phone_number     (account_id,phone_number)
#  index_campaign_recipients_on_campaign_id_and_status          (campaign_id,status)
#  index_campaign_recipients_on_contact_id_and_sent_at          (contact_id,sent_at)
#  index_campaign_recipients_on_conversation_id                 (conversation_id)
#  index_campaign_recipients_on_message_id                      (message_id)
#
class CampaignRecipient < ApplicationRecord
  belongs_to :campaign
  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true

  enum status: {
    pending: 0, processing: 1, sent: 2, delivered: 3,
    read: 4, failed: 5, replied: 6, cancelled: 7, skipped: 8
  }

  validates :phone_number, presence: true

  # Reivindica o destinatario de forma atomica (pending -> processing) para que a
  # engine nao despache o mesmo numero duas vezes em ticks concorrentes do
  # scheduler. Reflete o estado em memoria quando ganha a corrida.
  def claim!
    won = self.class.where(id: id, status: :pending)
                    .update_all(status: self.class.statuses[:processing], updated_at: Time.current) == 1
    self.status = :processing if won
    won
  end
end
