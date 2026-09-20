class Captain::Evidence::Context < ActiveSupport::CurrentAttributes
  attribute :scope, :publication_path

  def self.with_path(path, &)
    set(publication_path: path, &)
  end
end
