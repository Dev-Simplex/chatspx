# Grava uma fixture do harness a partir de um atendimento real.
#
# Ordem NÃO negociável: monta em memória → pseudonimiza → confere a trava → só então escreve.
# A trava roda antes de o byte tocar o disco, não antes do commit.
#
# Dois destinos, por decisão de 20/09:
#   - `corpus/` (fora do versionado): fala pseudonimizada, para eu ler e escrever a paráfrase;
#   - `spec/fixtures/.../harness/` (versionado): a fala do cliente já vira PARÁFRASE. Nada de
#     conversa real identificável entra no git, nem pseudonimizada.
#
# Fidelidade, declarada em cada fixture porque muda o que ela prova:
#   - `faithful`      — o retorno da tool está inteiro no trace;
#   - `reconstructed` — o `result_preview` veio truncado em 1.500 e o corpo está incompleto;
#   - `synthetic`     — escrita à mão, sem origem em produção (é o caso dos negativos e da conta 1).
#
# PORTA DO LEDGER: quando `captain_evidence_sources` existir na base (branch factguard-shadow),
# o corpo integral vem de lá e a fixture nasce `faithful` mesmo onde o preview truncou. Enquanto
# a tabela não existir, o gravador segue pelo preview — sem quebrar e sem fingir fidelidade.
class Spx::Harness::GravadorDeFixtures
  TABELA_LEDGER = 'captain_evidence_sources'.freeze
  PARAFRASEAR = '<PARAFRASEAR: escreva a intenção, não a fala>'.freeze
  FLAGS = %w[captain_tool_context captain_episode_window eval_enabled property_ref_context
             captain_fact_guard_shadow].freeze

  def initialize(conversation:, id:, desde: nil, ate: nil)
    @conversation = conversation
    @id = id
    @desde = desde
    @ate = ate
    @pseudo = Spx::Harness::Pseudonimizador.new(semente: id)
  end

  # Devolve o hash da fixture já pseudonimizado e conferido. NÃO escreve — quem escreve é
  # `gravar!`, e os dois caminhos passam pela mesma trava.
  def montar
    bruto = {
      'id' => @id,
      'fidelidade' => fidelidade,
      'origem' => origem,
      'relogio' => relogio.iso8601,
      'conta' => { 'flags' => flags_da_conta },
      'assistente' => assistente,
      'cache' => { 'estado' => 'vazio' },
      'mensagens' => mensagens,
      'chamadas' => chamadas
    }
    seguro = @pseudo.aplicar_em(bruto, nomes: nomes_proprios)
    Spx::Harness::Vazamento.conferir!(seguro.to_yaml, origem: @id)
    seguro
  end

  # `paraf: true` substitui a fala pelo marcador de paráfrase — é o que vai para o versionado.
  def gravar!(caminho, parafrasear: true)
    dados = montar
    dados = marcar_para_parafrase(dados) if parafrasear
    # Segunda conferida: o marcador não muda nada, mas gravar sem conferir o que de fato vai
    # ao disco seria confiar na etapa anterior.
    conteudo = Spx::Harness::Vazamento.conferir!(dados.to_yaml, origem: "#{@id} (#{caminho})")
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, conteudo)
    dados
  end

  private

  def marcar_para_parafrase(dados)
    copia = dados.deep_dup
    copia['mensagens'].each do |m|
      m['texto_sha'] = Digest::SHA1.hexdigest(m['texto'].to_s)[0, 12]
      m['texto'] = PARAFRASEAR
    end
    copia
  end

  def origem
    { 'conta' => @conversation.account_id, 'conversa' => @conversation.display_id,
      'episodio' => episodio&.seq, 'gravado_em' => Time.current.iso8601 }
  end

  # Relógio CONGELADO no instante do atendimento, não no da gravação: a conduta depende de
  # horário comercial e de dia da semana, e regravar em outro dia mudaria o cenário.
  def relogio
    mensagens_do_banco.first&.created_at || @conversation.created_at
  end

  def flags_da_conta
    (@conversation.account.custom_attributes || {}).slice(*FLAGS)
  end

  # Digest, não o texto: a versão de prompt/config precisa ser IDENTIFICÁVEL sem que o prompt
  # do cliente entre no repositório.
  def assistente
    a = assistente_do_atendimento
    return {} if a.nil?

    { 'id' => a.id, 'nome' => a.name,
      'config_digest' => Digest::SHA1.hexdigest(a.config.to_json)[0, 12],
      'instructions_digest' => Digest::SHA1.hexdigest(a.config['instructions'].to_s)[0, 12] }
  end

  def assistente_do_atendimento
    id = chamadas_do_banco.first&.captain_assistant_id
    id ? Captain::Assistant.find_by(id: id) : nil
  end

  def nomes_proprios
    [@conversation.contact&.name, @conversation.assignee&.name].compact
  end

  def mensagens
    mensagens_do_banco.map do |m|
      { 'de' => m.incoming? ? 'cliente' : 'ia', 'em' => m.created_at.iso8601, 'texto' => m.content.to_s }
    end
  end

  def chamadas
    chamadas_do_banco.each_with_index.map do |c, i|
      corpo = corpo_integral(c)
      { 'ordem' => i + 1, 'tool' => c.tool_name, 'args' => c.args, 'status' => c.status,
        'truncado' => truncado?(c) && corpo.nil?,
        'resultado' => corpo || c.result_preview.to_s, 'erro' => c.error }.compact
    end
  end

  # Uma única chamada truncada já impede a fixture de se dizer fiel.
  def fidelidade
    chamadas_do_banco.any? { |c| truncado?(c) && corpo_integral(c).nil? } ? 'reconstructed' : 'faithful'
  end

  def truncado?(chamada)
    chamada.result_preview.to_s.length >= Captain::Tools::TraceRecorder::RESULT_PREVIEW_LIMIT
  end

  # A porta. Sem a tabela, devolve nil e o chamador cai no preview.
  def corpo_integral(chamada)
    return nil unless ledger?

    @ledger_por_chamada ||= {}
    @ledger_por_chamada[chamada.id] ||= begin
      linha = ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT resultado FROM #{TABELA_LEDGER} WHERE conversation_id = ? AND tool_call_id = ? LIMIT 1",
           @conversation.id, chamada.id]
        )
      )
      linha && linha['resultado']
    end
  rescue StandardError => e
    Rails.logger.warn("[harness] ledger indisponível: #{e.class}: #{e.message}")
    nil
  end

  def ledger?
    return @ledger unless @ledger.nil?

    @ledger = ActiveRecord::Base.connection.table_exists?(TABELA_LEDGER)
  end

  def episodio
    @episodio ||= Captain::Conversation::EpisodeBoundary.new(conversation: @conversation).atual
  rescue StandardError
    nil
  end

  def mensagens_do_banco
    @mensagens_do_banco ||= janela(@conversation.messages.where(message_type: %i[incoming outgoing])
                                                .where(private: false)).order(:created_at).to_a
  end

  def chamadas_do_banco
    @chamadas_do_banco ||= janela(Captain::ToolCall.for_conversation(@conversation.id)).order(:created_at).to_a
  end

  def janela(escopo)
    escopo = escopo.where(created_at: @desde..) if @desde
    escopo = escopo.where(created_at: ..@ate) if @ate
    escopo
  end
end
