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

    destinatarios = Array(config['destinatarios']).map(&:to_s).select { |e| e.include?('@') }
    return Rails.logger.warn("[EvalDigest] conta #{account.id} habilitada sem destinatário válido") if destinatarios.empty?

    dados = coletar(account, config)
    # Silêncio quando o dia foi bom; alerta quando o próprio Eval parou de rodar. Digest
    # diário que chega sempre, mesmo vazio, é o primeiro a virar filtro de caixa de entrada.
    return if dados[:conversas].empty? && dados[:avaliados].positive?

    Spx::EvalDigestMailer.with(account: account).diario(account, dados, destinatarios).deliver_now
  end

  private

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
