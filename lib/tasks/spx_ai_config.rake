# Tarefas SPX · AI Config — receptor de change-sets de comportamento das IAs (Captain).
# O Almirante (control plane) invoca estes entrypoints por SSH apos a aprovacao do pleno.
# Ver docs/PLANO-GESTAO-IA-MULTIVM.md (v2).
#
# Uso:
#   bundle exec rails 'spx:ai_config:export[<account_id>,<assistant_id>]'   # baseline pro diff
#   bundle exec rails 'spx:ai_config:dry_run[<path/change_set.json>]'       # o que mudaria
#   bundle exec rails 'spx:ai_config:apply[<path/change_set.json>]'         # aplica (auditado)
#   bundle exec rails 'spx:ai_config:revert[<change_set_id>]'               # restaura snapshot
#
# Escopo v1 das operacoes: update_instructions, add_faq.
namespace :spx do
  namespace :ai_config do
    desc 'Exporta a config viva de um assistant (account_id, assistant_id) como JSON'
    task :export, %i[account_id assistant_id] => :environment do |_t, args|
      data = Spx::AiConfig::ConfigReader.export(
        account_id: Integer(args[:account_id]),
        assistant_id: Integer(args[:assistant_id])
      )
      puts JSON.pretty_generate(data)
    end

    desc 'Mostra o diff de um change-set (path do JSON) sem aplicar'
    task :dry_run, %i[path] => :environment do |_t, args|
      change_set = JSON.parse(File.read(args[:path]))
      diff = Spx::AiConfig::ChangeSetApplier.new(change_set).dry_run
      puts JSON.pretty_generate(diff)
    end

    desc 'Aplica um change-set aprovado (path do JSON) — transacional, idempotente, auditado'
    task :apply, %i[path] => :environment do |_t, args|
      change_set = JSON.parse(File.read(args[:path]))
      record = Spx::AiConfig::ChangeSetApplier.new(change_set).apply!
      puts "OK change_set=#{record.change_set_id} status=#{record.status} audit_id=#{record.id}"
    end

    desc 'Reverte um change-set aplicado (change_set_id) restaurando o snapshot'
    task :revert, %i[change_set_id] => :environment do |_t, args|
      record = Spx::AiConfig::ChangeSetApplier.revert!(args[:change_set_id])
      puts "REVERTIDO change_set=#{record.change_set_id} status=#{record.status}"
    end
  end
end
