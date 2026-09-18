# So o boot do web carimba o version.json. rake, runner, Sidekiq e o cron de 3 em 3 minutos
# (`rails messages:reconcile_team_id`) tambem carregam os initializers, e com o restart adiado para
# as 20:00 um `db:migrate` de dia carimbava o commit novo com o web velho no ar: a aba recarregava
# no front velho, guardava a versao nova e nunca mais recarregava. O arquivo tem que dizer
# "o web subiu com este commit", que e o que o front compara.
if defined?(Rails::Server)
  version = `git -C #{Rails.root} rev-parse --short HEAD 2>/dev/null`.strip
  version = 'unknown' if version.blank?

  version_file = Rails.public_path.join('version.json')
  File.write(version_file, { version: version, deployed_at: Time.now.to_i }.to_json)
end
