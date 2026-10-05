# Baseline congelado dos cenários de conduta.
#
# O `piso` responde "isto está aceitável?". Ele não responde "isto PIOROU?" — e é a segunda
# pergunta que pega a regressão de prompt. Um cenário que ia 6/6 e passou a ir 5/6 continua
# acima de um piso 5 e não acusa nada; foi exatamente assim que a mudança de 28/08 passou nos
# quatro cenários que pretendia consertar e quebrou um vizinho sem ninguém ver.
#
# O baseline é o par (acertos medidos, prompt com que foram medidos). O prompt entra junto
# porque comparar contra número medido em OUTRO prompt não diz nada: quando o digest muda, o
# baseline está vencido e é reportado como tal, não como queda.
class Spx::Conduta::Baseline
  # Queda de 1 acerto em 6 está dentro da variância entre rodadas idênticas (medido: o mesmo
  # prompt deu 5/6 e 6/6 no mesmo dia). Só a partir de 2 é sinal, não ruído.
  TOLERANCIA = 2

  Leitura = Struct.new(:estado, :texto, keyword_init: true) do
    def caiu?
      estado == :caiu
    end
  end

  def self.digest_do_prompt(assistant)
    Digest::SHA1.hexdigest(assistant.config['instructions'].to_s)[0, 12]
  end

  def self.ler(cenario, acertos:, assistant:)
    congelado = cenario['baseline']
    return Leitura.new(estado: :sem_baseline, texto: 'sem baseline') if congelado.blank?

    digest = digest_do_prompt(assistant)
    if congelado['prompt'].to_s != digest
      return Leitura.new(estado: :vencido,
                         texto: "baseline vencido (medido no prompt #{congelado['prompt']}, hoje #{digest})")
    end

    comparar(congelado, acertos)
  end

  def self.comparar(congelado, acertos)
    antes = congelado['acertos'].to_i
    delta = acertos - antes
    return Leitura.new(estado: :caiu, texto: "CAIU #{antes}->#{acertos} (baseline #{congelado['em']})") if
      delta <= -TOLERANCIA
    return Leitura.new(estado: :subiu, texto: "subiu #{antes}->#{acertos}") if delta.positive?

    Leitura.new(estado: :estavel, texto: "estável (#{antes})")
  end

  # O que o `congelar` grava. Data e prompt junto do número: um baseline sem os dois é um número
  # sem sentido seis meses depois.
  def self.congelar(acertos:, assistant:)
    { 'acertos' => acertos, 'prompt' => digest_do_prompt(assistant), 'em' => Date.current.iso8601 }
  end

  # Arquivo IRMÃO do de cenários. Separado de propósito: o arquivo de cenários é escrito por
  # gente e é metade comentário (o porquê de cada piso, o caso real que originou o cenário), e
  # reescrevê-lo por máquina apagaria isso. O baseline é só número e nasce para ser reescrito.
  def self.arquivo_de(caminho_dos_cenarios)
    "#{caminho_dos_cenarios.to_s.sub(/\.ya?ml\z/, '')}.baseline.yml"
  end

  def self.carregar(caminho_dos_cenarios)
    arquivo = arquivo_de(caminho_dos_cenarios)
    File.exist?(arquivo) ? (YAML.safe_load_file(arquivo) || {}) : {}
  end

  # Mescla o baseline nos cenários POR NOME. Cenário renomeado perde o baseline e volta a
  # aparecer como "sem baseline" — que é honesto: ninguém mediu aquele nome ainda.
  def self.aplicar(cenarios, caminho_dos_cenarios)
    congelados = carregar(caminho_dos_cenarios)
    cenarios.map { |c| c.merge('baseline' => congelados[c['nome']]).compact }
  end

  def self.gravar!(caminho_dos_cenarios, medicoes)
    arquivo = arquivo_de(caminho_dos_cenarios)
    anteriores = carregar(caminho_dos_cenarios)
    File.write(arquivo, anteriores.merge(medicoes).to_yaml)
    arquivo
  end
end
