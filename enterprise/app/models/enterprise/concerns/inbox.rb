module Enterprise::Concerns::Inbox
  extend ActiveSupport::Concern

  included do
    # A5: CaptainInbox vira ELEGIBILIDADE (has_one -> has_many). Uma inbox pode ter N
    # assistants elegíveis; a resposta é gated por ATRIBUIÇÃO (espelho dono da conversa).
    has_many :captain_inboxes, dependent: :destroy, class_name: 'CaptainInbox'
    has_many :captain_assistants,
             through: :captain_inboxes,
             class_name: 'Captain::Assistant'
    has_many :inbox_capacity_limits, dependent: :destroy
    before_create :ensure_create_permitted
  end

  def ensure_create_permitted
    raise CustomExceptions::Inbox::LimitExceeded.new({}) if account.inboxes.count >= account.usage_limits[:inboxes]
  end
end
