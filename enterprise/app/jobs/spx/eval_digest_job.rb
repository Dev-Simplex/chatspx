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

    emails = Array(config['destinatarios']).map(&:to_s).select { |e| e.include?('@') }
    webhook = config['webhook_url'].to_s.presence
    return Rails.logger.warn("[EvalDigest] conta #{account.id} habilitada sem destino") if emails.empty? && webhook.blank?

    dados = coletar(account, config)
    # Silêncio quando o dia foi bom; alerta quando o próprio Eval parou de rodar. Digest
    # diário que chega sempre, mesmo vazio, é o primeiro a virar filtro de caixa de entrada.
    return if dados[:conversas].empty? && dados[:avaliados].positive?

    Spx::EvalDigestMailer.with(account: account).diario(account, dados, emails).deliver_now if emails.any?
    entregar_webhook(account, dados, webhook) if webhook.present?
  end

  private

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
      eval_parado: dados[:conversas].empty? && dados[:avaliados].zero?,
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
    return "⚠️ #{account.name}: o avaliador não julgou nenhum atendimento nas últimas horas — provável cron parado." if
      dados[:conversas].empty? && dados[:avaliados].zero?

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
    linhas = achados(account, desde, severidades)

    {
      desde: desde,
      avaliados: avaliados,
      por_categoria: linhas.group_by { |l| l['categoria'] }.transform_values(&:size).sort_by { |_, n| -n },
      conversas: agrupar_por_conversa(linhas).first(limite),
      total_conversas: agrupar_por_conversa(linhas).size
    }
  end

  # SQL cru porque `response_findings` é um array jsonb e o filtro é por elemento — o
  # LATERAL evita carregar 10 mil avaliações no Ruby pra descartar quase todas.
  def achados(account, desde, severidades)
    lista = severidades.map { |s| ActiveRecord::Base.connection.quote(s) }.join(',')
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
