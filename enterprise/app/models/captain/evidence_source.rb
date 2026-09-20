class Captain::EvidenceSource < ApplicationRecord
  self.table_name = 'captain_evidence_sources'
  has_many :facts, class_name: 'Captain::EvidenceFact', foreign_key: :source_id, inverse_of: :source, dependent: :delete_all
  validates :account_id, :conversation_id, :episode_key, :run_id, :source_name, :source_version, :status, presence: true
end
