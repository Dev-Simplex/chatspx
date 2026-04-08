class Captain::Tools::Copilot::GetLabelsService < Captain::Tools::BaseTool
  def self.name
    'get_labels'
  end
  description 'List all available labels in the account'

  def execute
    labels = @assistant.account.labels.pluck(:title)
    return 'No labels found in this account' if labels.empty?

    "Available labels: #{labels.join(', ')}"
  end
end
