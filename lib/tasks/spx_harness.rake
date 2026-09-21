# Gravação de fixtures do harness offline.
#
# Conta e conversa são ARGUMENTO, nunca constante: o harness precisa aceitar cenário de
# qualquer tenant. Nada aqui é específico da conta 6.
#
# Dois destinos, e a diferença importa:
#   corpus  -> tmp/harness-corpus/ (gitignored). Fala pseudonimizada, para LER e escrever a
#              paráfrase. Não vai para o git.
#   fixture -> spec/fixtures/captain/harness/. A fala já vira marcador de paráfrase.
#
# Os dois passam pela mesma trava antes de escrever. Se ela acusar, nenhum arquivo é criado.
#
#   bundle exec rails "spx:harness:gravar[6,36940,tozi-condominio]"
#   bundle exec rails "spx:harness:gravar[6,36940,tozi-condominio,corpus]"
#   bundle exec rails "spx:harness:inventario[6,30]"
namespace :spx do
  namespace :harness do
    desc 'Grava fixture de um atendimento: gravar[conta,conversa,id,destino]'
    task :gravar, %i[conta conversa id destino] => :environment do |_t, args|
      conta = Integer(args[:conta].to_s)
      conversa = Integer(args[:conversa].to_s)
      id = args[:id].presence or abort('informe um id para a fixture')
      corpus = args[:destino].to_s == 'corpus'

      conversation = Conversation.find_by!(account_id: conta, display_id: conversa)
      caminho = if corpus
                  Rails.root.join('tmp/harness-corpus', "#{id}.yml")
                else
                  Rails.root.join('spec/fixtures/captain/harness', "#{id}.yml")
                end

      dados = Spx::Harness::GravadorDeFixtures
              .new(conversation: conversation, id: id)
              .gravar!(caminho.to_s, parafrasear: !corpus)

      puts "gravado: #{caminho}"
      puts "  fidelidade: #{dados['fidelidade']}"
      puts "  mensagens: #{dados['mensagens'].size} | chamadas: #{dados['chamadas'].size}"
      puts "  truncadas: #{dados['chamadas'].count { |c| c['truncado'] }}"
      puts '  ATENÇÃO: fala substituída por marcador — escreva a paráfrase antes de usar.' unless corpus
    end

    # Antes de gravar qualquer coisa, saber o que dá para gravar: quantos atendimentos e qual a
    # proporção fiel x reconstruída. A conta de 20/09 na Tozi deu 5,6% truncado no geral e 23%
    # no buscar_imovel — a truncagem não é uniforme, é concentrada na tool que mais importa.
    desc 'Inventário do que é gravável: inventario[conta,dias]'
    task :inventario, %i[conta dias] => :environment do |_t, args|
      conta = Integer(args[:conta].to_s)
      dias = Integer((args[:dias] || 30).to_s)
      limite = Captain::Tools::TraceRecorder::RESULT_PREVIEW_LIMIT

      escopo = Captain::ToolCall.where(account_id: conta).where(created_at: dias.days.ago..)
      total = escopo.count
      truncadas = escopo.where('length(result_preview) >= ?', limite).count

      puts "conta #{conta} · #{dias} dias"
      puts "  chamadas: #{total} | truncadas: #{truncadas} (#{percentual(truncadas, total)})"
      puts "  ledger integral disponível: #{ActiveRecord::Base.connection.table_exists?('captain_evidence_sources')}"
      puts '  por ferramenta (truncadas/total):'
      escopo.group(:tool_name).count.sort_by { |_, c| -c }.each do |nome, c|
        t = escopo.where(tool_name: nome).where('length(result_preview) >= ?', limite).count
        puts format('    %<tool>-28s %<trunc>4d/%<total>-6d %<pct>s',
                    tool: nome, trunc: t, total: c, pct: percentual(t, c))
      end
    end

    def percentual(parte, todo)
      todo.to_i.zero? ? '—' : format('%.1f%%', parte * 100.0 / todo)
    end
  end
end
