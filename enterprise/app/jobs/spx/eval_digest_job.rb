# Digest diário do Eval: leva o que o juiz já achou até quem opera.
#
# Por que existe: o Eval avalia de hora em hora e produz em volume — medido numa conta em
# 28/08/2026, 30 dias: 583 `contradisse_tool`, 376 `promessa_indevida`, 311 `alucinacao`, num
# total de 380 conversas com finding grave da IA. Nada disso chegava a ninguém: o resultado
# vive num painel que alguém precisa abrir, e a única ação com rastro (a anotação #eval) tinha
# 8 registros desde sempre. O gargalo nunca foi detecção, foi consumo.
#
# Opt-in por conta. Sem `custom_attributes['eval_digest']['enabled']` a conta não recebe nada —
# e o destinatário é lista EXPLÍCITA, nunca "todos os admins": a conta medida tem 25 admins, e
# e-mail que chega para 25 pessoas não é de ninguém.
class Spx::EvalDigestJob < ApplicationJob
  queue_as :low

  JANELA_PADRAO_HORAS = 24
  LIMITE_PADRAO = 15
  SEVERIDADES_PADRAO = %w[alta].freeze

  def perform(account)
    config = digest_config(account)
    return unless config['enabled']

    destinos = destinos_de(config)
    return Rails.logger.warn("[EvalDigest] conta #{account.id} habilitada sem destino") if destinos.empty?

    dados = coletar(account, config)
    return unless vale_avisar?(dados, config)

    entregar(account, dados, destinos)
  end

  private

  def destinos_de(config)
    emails = Array(config['destinatarios']).map(&:to_s).select { |e| e.include?('@') }
    { emails: emails, webhook: config['webhook_url'].to_s.presence }.compact_blank
  end

  # Por padrão: silêncio quando o dia foi bom, alerta quando o próprio Eval parou. Digest que
  # chega todo dia, mesmo vazio, é o primeiro a virar filtro de caixa de entrada.
  #
  # Só que o silêncio é AMBÍGUO para quem espera, e isso custou caro: entre 01 e 04/09 o juiz
  # estourava em todo episódio com atendimento e não gravava veredito nenhum; o digest via
  # zero falha grave e calou por quatro dias, enquanto quem esperava não tinha como saber se
  # o dia tinha sido limpo ou se o sistema estava cego.
  #
  # `avisar_dia_limpo` troca o silêncio por uma confirmação de que o ciclo rodou e o que ele
  # viu. Opt-in por conta: quem prefere só ser incomodado quando há problema não muda de
  # comportamento, e quem prefere o sinal de vida diário liga a chave.
  def vale_avisar?(dados, config = {})
    return true if config['avisar_dia_limpo']

    dados[:conversas].any? || dados[:avaliados].zero?
  end

  # Distingue os três estados que o digest pode reportar. `eval_parado` é o mais grave e vem
  # primeiro: sem nada julgado, "nenhuma falha" não é notícia boa, é ausência de medição.
  def situacao(dados)
    return :eval_parado if dados[:avaliados].zero?
    return :dia_limpo if dados[:conversas].empty?

    :com_falhas
  end

  def entregar(account, dados, destinos)
    Spx::EvalDigestMailer.with(account: account).diario(account, dados, destinos[:emails]).deliver_now if
      destinos[:emails].present?
    entregar_webhook(account, dados, destinos[:webhook]) if destinos[:webhook].present?
  end

  # Webhook antes de e-mail na ordem de preferência real: e-mail é onde o digest morre
  # quando a operação vive em outro lugar. Daqui a pessoa pluga no que ela já usa (n8n,
  # Telegram, Discord, Slack) sem que este job precise conhecer cada canal.
  #
  # O payload traz os dados ESTRUTURADOS e um campo `texto` já formatado, de propósito: um
  # consumidor que só encaminha usa o `texto` direto; um que monta a própria mensagem usa o
  # resto. Um payload, os dois usos, nenhuma opção a mais pra configurar errado.
  def entregar_webhook(account, dados, url)
    HTTParty.post(url,
                  body: payload(account, dados).to_json,
                  headers: { 'Content-Type' => 'application/json' },
                  timeout: 15)
  rescue StandardError => e
    # Igual ao mailer, que tem rescue de SMTP: falha de entrega não pode derrubar o cron.
    Rails.logger.warn("[EvalDigest] webhook da conta #{account.id} falhou: #{e.message}")
  end

  def payload(account, dados)
    {
      conta: { id: account.id, nome: account.name },
      janela_desde: dados[:desde].iso8601,
      avaliados: dados[:avaliados],
      eval_parado: situacao(dados) == :eval_parado,
      # Quem consome o webhook (n8n, Telegram, Slack) decide o que fazer com cada estado sem
      # ter que inferir a partir dos contadores — inferência que este job mesmo errou.
      situacao: situacao(dados),
      total_conversas: dados[:total_conversas],
      por_categoria: dados[:por_categoria].to_h,
      conversas: dados[:conversas].map { |c| c.merge(url: url_da_conversa(account, c[:display_id])) },
      texto: texto(account, dados)
    }
  end

  def url_da_conversa(account, display_id)
    base = ENV.fetch('FRONTEND_URL', nil)
    base.present? ? "#{base}/app/accounts/#{account.id}/conversations/#{display_id}" : nil
  end

  # Texto pronto pra encaminhar, curto o bastante pra caber numa mensagem de WhatsApp ou
  # Telegram sem virar parede.
  def texto(account, dados)
    case situacao(dados)
    when :eval_parado
      return "⚠️ #{account.name}: o avaliador não julgou nenhum atendimento nas últimas horas — provável cron parado."
    when :dia_limpo
      # Diz o que foi MEDIDO, não só que está tudo bem: "nenhuma falha grave" sem o número de
      # atendimentos avaliados é indistinguível de avaliador parado — foi essa ambiguidade que
      # deixou quatro dias de cegueira passarem por dia bom.
      return "✅ #{account.name} — #{dados[:avaliados]} atendimento(s) avaliado(s) nas últimas " \
             'horas, nenhum com falha grave da IA.'
    end

    cab = "🔎 #{account.name} — #{dados[:total_conversas]} conversa(s) da IA com falha grave " \
          "(de #{dados[:avaliados]} avaliadas)"
    tipos = dados[:por_categoria].first(4).map { |c, n| "#{c} (#{n})" }.join(' · ')
    linhas = dados[:conversas].first(5).map do |c|
      cats = c[:findings].map { |f| f['categoria'] }.uniq.join(', ')
      "• #{c[:display_id]} — nota #{c[:nota] || '—'} — #{cats}"
    end
    [cab, tipos, '', *linhas].join("\n")
  end

  def digest_config(account)
    (account.custom_attributes || {})['eval_digest'].presence || {}
  end

  def coletar(account, config)
    desde = (config['janela_horas'] || JANELA_PADRAO_HORAS).to_i.hours.ago
    severidades = Array(config['severidades'].presence || SEVERIDADES_PADRAO)
    limite = (config['limite'] || LIMITE_PADRAO).to_i

    avaliados = Captain::ConversationEval.where(account_id: account.id).where(created_at: desde..).count
    linhas = achados(account, desde, severidades, config['nota_maxima'])
    conversas = agrupar_por_conversa(linhas)

    {
      desde: desde,
      avaliados: avaliados,
      por_categoria: linhas.group_by { |l| l['categoria'] }.transform_values(&:size).sort_by { |_, n| -n },
      conversas: conversas.first(limite),
      total_conversas: conversas.size
    }
  end

  # SQL cru porque `response_findings` é um array jsonb e o filtro é por elemento — o
  # LATERAL evita carregar 10 mil avaliações no Ruby pra descartar quase todas.
  #
  # `nota_maxima` é o que transforma o digest de relatório em aviso. Sem corte, uma conta
  # medida em 28/08/2026 gerava ~13 conversas por dia — volume de relatório, que vira
  # paisagem. Com corte em 2, a média cai para 2,5 por dia (pico 6): cabe numa mensagem
  # de grupo e a maior parte dos dias fica em silêncio.
  def achados(account, desde, severidades, nota_maxima = nil)
    lista = severidades.map { |s| ActiveRecord::Base.connection.quote(s) }.join(',')
    # Avaliação SEM nota fica de fora quando há corte: nota nula não é "nota boa", mas
    # também não é evidência de falha — e o objetivo aqui é a fila do que precisa de ação.
    corte = nota_maxima.present? ? "AND e.nota IS NOT NULL AND e.nota <= #{nota_maxima.to_i}" : ''
    ActiveRecord::Base.connection.select_all(<<~SQL.squish).to_a
      SELECT c.display_id, c.id conversation_id, e.nota, e.resumo,
             f->>'categoria' categoria, f->>'severidade' severidade,
             f->>'trecho' trecho, f->>'porque' porque
      FROM captain_conversation_evals e
      JOIN conversations c ON c.id = e.conversation_id,
           LATERAL jsonb_array_elements(
             CASE jsonb_typeof(e.response_findings) WHEN 'array' THEN e.response_findings ELSE '[]'::jsonb END
           ) f
      WHERE e.account_id = #{account.id.to_i}
        AND e.created_at >= #{ActiveRecord::Base.connection.quote(desde)}
        AND f->>'quem' = 'ia'
        AND f->>'severidade' IN (#{lista})
        #{corte}
      ORDER BY e.nota NULLS LAST, c.display_id
    SQL
  end

  # Uma linha por CONVERSA, com os findings dela dentro — o operador abre conversas, não
  # findings soltos. Pior nota primeiro.
  def agrupar_por_conversa(linhas)
    agrupadas = linhas.group_by { |l| l['display_id'] }.map do |display_id, itens|
      { display_id: display_id, conversation_id: itens.first['conversation_id'],
        nota: itens.first['nota'], resumo: itens.first['resumo'],
        findings: itens.map { |i| i.slice('categoria', 'trecho', 'porque') } }
    end
    agrupadas.sort_by { |c| [c[:nota] || 99, c[:display_id]] }
  end
end
