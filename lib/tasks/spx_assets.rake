namespace :spx do
  namespace :assets do
    desc 'Falha se os assets Vite contiverem código de desenvolvimento do Vue'
    # A inspeção dos arquivos não precisa inicializar o banco nem os serviços da aplicação.
    task :verificar_producao do # rubocop:disable Rails/RakeEnvironment
      assets = Dir[Rails.public_path.join('vite/assets/*.js')]
      abort 'Nenhum asset JavaScript encontrado em public/vite/assets; execute assets:precompile.' if assets.empty?

      # [Vue warn] também existe na compatibilidade Vue 2 do Sentry em produção.
      development_assets = assets.select { |asset| File.read(asset).include?('Extraneous non-props attributes') }
      abort "Assets com código de desenvolvimento do Vue:\n#{development_assets.join("\n")}" if development_assets.any?

      puts "Verificação de produção OK: #{assets.size} assets JavaScript sem marcador de desenvolvimento do Vue."
    end
  end
end
