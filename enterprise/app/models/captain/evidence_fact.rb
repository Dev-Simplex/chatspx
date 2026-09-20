class Captain::EvidenceFact < ApplicationRecord
  self.table_name = 'captain_evidence_facts'
  belongs_to :source, class_name: 'Captain::EvidenceSource'
end
