# Cache-Control headers for ActiveStorage blob responses
# Allows browsers to cache audio/video blobs and avoid re-downloading on each play
Rails.application.config.after_initialize do
  ActiveStorage::BaseController.after_action only: [:show] do
    if response.headers['Content-Type']&.start_with?('audio/', 'video/')
      response.headers['Cache-Control'] = 'public, max-age=3600, stale-while-revalidate=86400'
    end
  end
end
