every 1.day, at: '2:00 am' do
  runner "NpsExpirationJob.perform_now"
end
