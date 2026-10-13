# SUP-1415: limpa fichas com o MESMO telefone na mesma conta antes do indice unico (Contacts::PhoneDuplicateCleanup).
#
#   bundle exec rake contacts:telefone_duplicado              # SIMULA: so lista o que faria
#   APLICAR=1 bundle exec rake contacts:telefone_duplicado    # faz, com backup JSON de cada grupo antes
#   CONTA=5 ...                                               # so uma conta
#   BACKUP_DIR=...                                            # padrao ~/backups/contatos-telefone-duplicado
namespace :contacts do
  desc 'Lista (ou junta, com APLICAR=1) fichas com o mesmo telefone na mesma conta'
  task telefone_duplicado: :environment do
    apply = ENV['APLICAR'] == '1'
    backup_dir = ENV.fetch('BACKUP_DIR', File.expand_path('~/backups/contatos-telefone-duplicado'))
    groups = Contacts::PhoneDuplicateCleanup.new(account_id: ENV.fetch('CONTA', nil), apply: apply, backup_dir: backup_dir).perform
    removed = groups.sum { |group| group.to_delete.size + group.to_merge.size }
    puts apply ? "Feito: #{removed} ficha(s) a menos. Backup em #{backup_dir}" : "Faria: #{removed} ficha(s) a menos. Rode com APLICAR=1."
  end
end
