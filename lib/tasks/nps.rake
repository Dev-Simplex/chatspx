namespace :nps do
  desc 'Expire old NPS surveys'
  task expire: :environment do
    NpsExpirationJob.perform_now
  end
end
