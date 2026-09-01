class Avatar::AvatarFromFaviconJob < ApplicationJob
  queue_as :purgable

  def perform(company)
    return if company.domain.blank?
    return if company.avatar.attached?

    favicon_url = "https://www.google.com/s2/favicons?domain=#{company.domain}&sz=256"
    # AvatarFromUrlJob recebe (type, id, url) desde 87095e111b (AR object -> IDs);
    # este callsite ficou para tras naquela conversao e estourava ArgumentError.
    Avatar::AvatarFromUrlJob.perform_now(company.class.name, company.id, favicon_url)
  end
end
