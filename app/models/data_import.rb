# == Schema Information
#
# Table name: data_imports
#
#  id                :bigint           not null, primary key
#  data_type         :string           not null
#  processed_records :integer
#  processing_errors :text
#  status            :integer          default("pending"), not null
#  total_records     :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_data_imports_on_account_id  (account_id)
#
class DataImport < ApplicationRecord
  belongs_to :account
  validates :data_type, inclusion: { in: %w[contacts catalog_products], message: I18n.t('errors.data_import.data_type.invalid') }
  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  has_one_attached :import_file
  has_one_attached :failed_records

  after_create_commit :process_data_import

  private

  # Cada tipo tem o seu processador: o DataImportJob é escrito em cima de contato (o TODO no topo
  # dele diz isso), e o catálogo (C5) precisa de outra regra — casar pelo SKU em vez de inserir.
  PROCESSADORES = { 'catalog_products' => 'Catalog::ProductImportJob' }.freeze

  def process_data_import
    # we wait for the file to be uploaded to the cloud
    job = PROCESSADORES.fetch(data_type, 'DataImportJob').constantize
    job.set(wait: 1.minute).perform_later(id)
  end
end
