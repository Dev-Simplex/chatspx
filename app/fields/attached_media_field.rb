require 'administrate/field/base'

# Campo minimo para um has_one_attached: no index/show mostra um link que abre o arquivo, e
# "-" quando nao ha anexo. O Administrate nao traz campo pronto para ActiveStorage.
class AttachedMediaField < Administrate::Field::Base
  def attached?
    data.respond_to?(:attached?) && data.attached?
  end

  def url
    Rails.application.routes.url_helpers.rails_blob_url(data, only_path: true)
  end

  def filename
    data.filename.to_s
  end
end
