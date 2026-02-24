class Captain::Llm::UpdateEmbeddingJob < ApplicationJob
  queue_as :low

  def perform(record, content)
    account_id = record.account_id
    embedding = Captain::Llm::EmbeddingService.new(account_id: account_id).get_embedding(content)
    record.update!(embedding: embedding)
  rescue Llm::Config::MissingAccountApiKeyError => e
    Rails.logger.warn("[#{self.class.name}] Skipping embedding update for #{record.class.name}##{record.id}: #{e.message}")
  end
end
