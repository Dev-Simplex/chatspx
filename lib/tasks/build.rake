# ref: https://github.com/rails/rails/issues/43906#issuecomment-1094380699
# https://github.com/rails/rails/issues/43906#issuecomment-1099992310
task before_assets_precompile: :environment do
  # run a command which starts your packaging
  system('pnpm install')
  system('echo "-------------- Bulding SDK for Production --------------"')
  system('pnpm run build:sdk')
  # Bloco 5.08 — o coletor de origem e um artefato SEPARADO do sdk.js, e precisa ser
  # construido aqui: o carregador fino (sdk/tracking/loader.js) o busca por URL em runtime,
  # entao ele nunca entra no bundle do SDK. Sem esta linha o coletor simplesmente nao existe
  # em producao, e o `import()` do carregador cai no `catch` — falha silenciosa, do tipo que
  # so aparece como "a atribuicao parou de funcionar" semanas depois.
  system('echo "-------------- Bulding origin collector (5.08) --------------"')
  system('pnpm run build:tracking')
  system('echo "-------------- Bulding App for Production --------------"')
end

# every time you execute 'rake assets:precompile'
# run 'before_assets_precompile' first
Rake::Task['assets:precompile'].enhance %w[before_assets_precompile]
