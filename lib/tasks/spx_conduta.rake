# Regressão de CONDUTA: roda cenários congelados contra os prompts que estão no banco e
# reporta quantas rodadas bateram o esperado. Nada é enviado ao cliente — cada rodada monta
# o histórico numa conversa de rascunho e é revertida.
#
# Por que existe: em 28/08 uma mudança de conduta foi medida SÓ nos cenários que ela
# pretendia consertar, passou nos quatro, e quebrou um cenário vizinho — a IA passou a
# afirmar que imóveis avulsos ficavam em condomínio fechado. O defeito só apareceu horas
# depois, numa conversa real, pelo gerente do cliente. Prompt não tem teste de regressão;
# isto é o mínimo que faz as vezes de um.
#
# Uso:
#   bundle exec rails "spx:conduta:regressao[docs/clientes/tozi/conduta-regressao.yml,6]"
#   bundle exec rails "spx:conduta:regressao[<arquivo>,6,visita]"   # filtra por tag
#
# N >= 6 por cenário é o piso: com N=2 e N=3, no mesmo dia e no mesmo prompt, a leitura saiu
# errada nos dois sentidos. A variância entre rodadas idênticas é maior que o efeito medido.
namespace :spx do
  namespace :conduta do
    desc 'Roda cenários de conduta contra os prompts do banco (nada é enviado)'
    task :regressao, %i[arquivo rodadas tag] => :environment do |_t, args|
      arquivo = args[:arquivo] or abort('informe o arquivo de cenários')
      rodadas = (args[:rodadas] || 6).to_i
      abort("arquivo não encontrado: #{arquivo}") unless File.exist?(arquivo)

      spec = YAML.safe_load_file(arquivo)
      conta = spec.fetch('account_id')
      conversa = Conversation.find_by!(account_id: conta, display_id: spec.fetch('conversa_rascunho'))
      cenarios = spec.fetch('cenarios').select { |c| args[:tag].blank? || Array(c['tags']).include?(args[:tag]) }
      abort('nenhum cenário selecionado') if cenarios.empty?

      puts "conta #{conta} · rascunho ##{conversa.display_id} · #{cenarios.size} cenário(s) × #{rodadas} rodada(s)"
      puts

      falhas = Spx::Conduta::Regressao.new(conversa: conversa, rodadas: rodadas).executar(cenarios) do |linha|
        puts linha
      end

      puts
      if falhas.zero?
        puts '✅ todos os cenários dentro do piso'
      else
        puts "❌ #{falhas} cenário(s) abaixo do piso"
        abort
      end
    end
  end
end
