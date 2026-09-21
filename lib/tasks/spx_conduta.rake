# Regressão de CONDUTA — nível 2 do harness: o sujeito é o MODELO.
#
# Roda cenários congelados contra os prompts que estão no banco e reporta quantas rodadas
# bateram o esperado. Nada é enviado ao cliente — cada rodada monta o histórico numa conversa
# de rascunho e é revertida.
#
# Por que existe: em 28/08 uma mudança de conduta foi medida SÓ nos cenários que ela pretendia
# consertar, passou nos quatro, e quebrou um cenário vizinho — a IA passou a afirmar que
# imóveis avulsos ficavam em condomínio fechado. O defeito só apareceu horas depois, numa
# conversa real, pelo gerente do cliente. Prompt não tem teste de regressão; isto é o mínimo
# que faz as vezes de um.
#
# Difere do NÍVEL 1 (spec/enterprise/services/spx/harness/nivel1) em tudo que importa: lá o
# modelo é roteirizado, a asserção é binária e o custo é zero, então roda na CI a cada PR. Aqui
# o modelo é o de verdade, o resultado é estatístico e cada rodada custa — então é disparo à
# mão, antes e depois de mexer em prompt.
#
# Uso:
#   bundle exec rails "spx:conduta:regressao[docs/clientes/tozi/conduta-regressao.yml,6]"
#   bundle exec rails "spx:conduta:regressao[<arquivo>,6,visita]"          # filtra por tag
#   bundle exec rails "spx:conduta:regressao[<arquivo>,6,,3,2159]"         # outra conta/conversa
#   bundle exec rails "spx:conduta:congelar[<arquivo>,6]"                  # grava o baseline
#
# N >= 6 por cenário é o piso: com N=2 e N=3, no mesmo dia e no mesmo prompt, a leitura saiu
# errada nos dois sentidos. A variância entre rodadas idênticas é maior que o efeito medido.
# Helpers no topo, fora do bloco do namespace: rake carrega o arquivo inteiro e os métodos
# ficam disponíveis do mesmo jeito. Dentro do bloco eles estouram o Metrics/BlockLength, e
# aumentar o limite para caber esconderia tarefa grande de verdade no futuro.
def rodar_cenarios(args, congelar:)
  arquivo = args[:arquivo] or abort('informe o arquivo de cenários')
  abort("arquivo não encontrado: #{arquivo}") unless File.exist?(arquivo)

  spec = YAML.safe_load_file(arquivo)
  conversa = conversa_alvo(spec, args)
  cenarios = selecionar(spec, arquivo, args[:tag])
  rodadas = (args[:rodadas] || 6).to_i

  puts "conta #{conversa.account_id} · rascunho ##{conversa.display_id} · " \
       "#{cenarios.size} cenário(s) × #{rodadas} rodada(s)"
  puts

  motor = Spx::Conduta::Regressao.new(conversation: conversa, rodadas: rodadas)
  falhas = motor.executar(cenarios) { |linha| puts linha }

  puts
  puts "baseline gravado: #{Spx::Conduta::Baseline.gravar!(arquivo, motor.medicoes)}" if congelar
  encerrar(falhas)
end

# Conta e conversa saem do arquivo, e a linha de comando pode sobrescrever as duas: o mesmo
# conjunto de cenários precisa poder rodar contra a homologação de outro cliente sem virar
# um segundo arquivo que envelhece em paralelo.
def conversa_alvo(spec, args)
  conta = (args[:conta].presence || spec.fetch('account_id')).to_i
  display = (args[:conversa].presence || spec.fetch('conversa_rascunho')).to_i
  Conversation.find_by!(account_id: conta, display_id: display)
end

def selecionar(spec, arquivo, tag)
  cenarios = Spx::Conduta::Baseline.aplicar(spec.fetch('cenarios'), arquivo)
                                   .select { |c| tag.blank? || Array(c['tags']).include?(tag) }
  abort('nenhum cenário selecionado') if cenarios.empty?

  cenarios
end

def encerrar(falhas)
  if falhas.zero?
    puts '✅ todos os cenários dentro do piso e sem queda contra o baseline'
  else
    puts "❌ #{falhas} cenário(s) abaixo do piso ou em queda"
    abort
  end
end

namespace :spx do
  namespace :conduta do
    desc 'Roda cenários de conduta contra os prompts do banco (nada é enviado)'
    task :regressao, %i[arquivo rodadas tag conta conversa] => :environment do |_t, args|
      rodar_cenarios(args, congelar: false)
    end

    # Congela o resultado MEDIDO como novo baseline. Rodar depois de uma mudança de prompt que
    # já foi conferida — congelar sem olhar transforma regressão em "novo normal", que é o
    # oposto do que o baseline serve.
    desc 'Roda e grava o resultado como baseline dos cenários'
    task :congelar, %i[arquivo rodadas tag conta conversa] => :environment do |_t, args|
      rodar_cenarios(args, congelar: true)
    end
  end
end
