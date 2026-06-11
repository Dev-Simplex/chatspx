# Captain Sync — exporta/importa um Assistente de IA (Captain) entre ambientes.
#
# Move SÓ as tabelas captain_* de UM assistente/conta — nunca o banco todo.
# Embeddings (vector) viajam junto; inbox NÃO é religada automaticamente (ids
# diferem entre ambientes) — o admin religa na tela. content_search (tsvector)
# é regenerado pelo destino.
#
# Uso:
#   bundle exec rake "captain:export[<assistant_id>, /caminho/saida.json]"
#   bundle exec rake "captain:import[/caminho/dump.json, <account_id_destino>]"        # DRY-RUN (não grava)
#   APPLY=1 bundle exec rake "captain:import[/caminho/dump.json, <account_id_destino>]" # aplica de verdade
#
# Toda importação faz BACKUP automático do estado atual do destino antes de gravar.

namespace :captain do
  # colunas que NÃO viajam (id é remapeado; content_search é gerado pelo DB)
  SKIP_COLS = %w[id content_search created_at updated_at].freeze

  def dump_record(rec)
    rec.attributes.except(*SKIP_COLS)
  end

  def export_assistant(assistant)
    {
      'schema_version' => 1,
      'source_account_id' => assistant.account_id,
      'assistant' => dump_record(assistant),
      'scenarios' => assistant.scenarios.map { |r| dump_record(r) },
      'responses' => assistant.responses.map { |r| dump_record(r) },
      'documents' => assistant.documents.map { |d| dump_record(d).merge('_src_id' => d.id) },
      'document_chunks' => assistant.document_chunks.map { |c| dump_record(c).merge('_src_document_id' => c.captain_document_id) },
      'custom_tools' => assistant.account.captain_custom_tools.map { |t| dump_record(t) },
      'inbox_names' => assistant.inboxes.map(&:name)
    }
  end

  desc 'Exporta um assistente Captain (captain_*) para JSON. Args: assistant_id, out_file'
  task :export, %i[assistant_id out_file] => :environment do |_t, args|
    assistant = Captain::Assistant.find(args[:assistant_id])
    data = export_assistant(assistant)
    out = args[:out_file].presence || "tmp/captain_assistant_#{assistant.id}.json"
    File.write(out, JSON.pretty_generate(data))
    puts "✅ Exportado: #{assistant.name} (conta #{assistant.account_id})"
    puts "   #{data['responses'].size} respostas · #{data['documents'].size} docs · " \
         "#{data['document_chunks'].size} chunks · #{data['scenarios'].size} cenários · " \
         "#{data['custom_tools'].size} tools · inboxes: #{data['inbox_names'].join(', ')}"
    puts "   → #{out}"
  end

  desc 'Importa um assistente Captain num ambiente. Args: in_file, target_account_id (DRY-RUN; APPLY=1 grava)'
  task :import, %i[in_file target_account_id] => :environment do |_t, args|
    apply = ENV['APPLY'] == '1'
    data = JSON.parse(File.read(args[:in_file]))
    target_account = Account.find(args[:target_account_id])
    name = data.dig('assistant', 'name')

    existing = target_account.captain_assistants.find_by(name: name)
    puts "🎯 Destino: conta #{target_account.id} (#{target_account.name})"
    puts "   Assistente \"#{name}\": #{existing ? "JÁ EXISTE (id #{existing.id}) → será SUBSTITUÍDO" : 'NOVO → será criado'}"
    puts "   Vai gravar: #{data['responses'].size} respostas · #{data['documents'].size} docs · " \
         "#{data['document_chunks'].size} chunks · #{data['scenarios'].size} cenários · #{data['custom_tools'].size} tools"
    puts "   ⚠️ Inboxes NÃO são religadas (#{data['inbox_names'].join(', ')}) — religar na tela após importar."

    unless apply
      puts "\n🟡 DRY-RUN — nada foi gravado. Rode com APPLY=1 para aplicar."
      next
    end

    # BACKUP automático do destino antes de qualquer escrita
    if existing
      backup = "tmp/captain_backup_acc#{target_account.id}_#{existing.id}_#{Time.now.utc.strftime('%Y%m%d%H%M%S')}.json"
      File.write(backup, JSON.pretty_generate(export_assistant(existing)))
      puts "💾 Backup do estado atual: #{backup}"
    end

    ActiveRecord::Base.transaction do
      assistant = existing || target_account.captain_assistants.new
      assistant.assign_attributes(data['assistant'].merge('account_id' => target_account.id))
      assistant.save!

      # substitui os filhos (idempotente)
      assistant.responses.delete_all
      assistant.document_chunks.delete_all
      assistant.documents.delete_all
      assistant.scenarios.delete_all

      data['scenarios'].each do |r|
        assistant.scenarios.create!(r.merge('account_id' => target_account.id))
      end

      # documents: cria e mapeia src_id -> novo id (p/ chunks e responses polimórficas)
      doc_map = {}
      data['documents'].each do |d|
        src = d.delete('_src_id')
        doc = assistant.documents.create!(d.merge('account_id' => target_account.id))
        doc_map[src] = doc.id
      end

      data['document_chunks'].each do |c|
        src_doc = c.delete('_src_document_id')
        assistant.document_chunks.create!(
          c.merge('account_id' => target_account.id, 'captain_document_id' => doc_map[src_doc])
        )
      end

      data['responses'].each do |r|
        # documentable polimórfico: remapeia se aponta p/ um Captain::Document migrado
        if r['documentable_type'] == 'Captain::Document'
          r['documentable_id'] = doc_map[r['documentable_id']]
        end
        assistant.responses.create!(r.merge('account_id' => target_account.id))
      end

      data['custom_tools'].each do |t|
        tool = target_account.captain_custom_tools.find_or_initialize_by(slug: t['slug'])
        tool.assign_attributes(t.merge('account_id' => target_account.id))
        tool.save!
      end
    end

    puts "✅ Importado com sucesso para a conta #{target_account.id}."
    puts "   👉 Religue o assistente nos inboxes pela tela (Agentes IA)."
  end
end
