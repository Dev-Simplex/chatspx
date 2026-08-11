# Recebe leads dos formularios do site institucional.
#
# POST /webhooks/site_leads  — JSON + segredo compartilhado no header X-SPX-Token.
#
# Lead de site tem a MESMA natureza do lead do Meta: evento unico que chega, de alguem
# que preencheu um formulario e nunca escreveu no WhatsApp. Por isso reaproveita a engine
# do Meta::LeadAds::CreateConversationService (que ja e generica: recebe hook + lead) em
# vez da estrutura de campanhas, que e lote frio iniciado por nos.
class Webhooks::SiteLeadsController < ActionController::API
  APP_ID = 'site_leads'.freeze
  SECRET_HEADER = 'X-SPX-Token'.freeze
  PERMITTED = %w[nome telefone email codigo_imovel jornada].freeze

  def process_payload
    hook = authenticated_hook
    return head :unauthorized if hook.nil?

    payload = JSON.parse(request.raw_post)
    # Sem telefone nao ha como abrir a conversa no WhatsApp — recusa explicita, pra quem
    # integra o site descobrir na hora e nao virar lead pago que some em silencio.
    if payload['telefone'].to_s.strip.blank?
      render status: :unprocessable_entity, json: { error: 'telefone é obrigatório' }
      return
    end

    Webhooks::SiteLeadJob.perform_later(hook.id, payload.slice(*PERMITTED))
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.warn("Site Leads webhook: JSON inválido - #{e.message}")
    head :bad_request
  end

  private

  # O proprio segredo seleciona o hook — e portanto a conta. Nao ha id na URL: um id
  # publico so daria a quem chama a chance de errar de conta. `secure_compare` evita
  # vazar o segredo pela diferenca de tempo entre uma comparacao que falha no 1o
  # caractere e outra que falha no ultimo.
  def authenticated_hook
    presented = request.headers[SECRET_HEADER].to_s
    return nil if presented.blank?

    Integrations::Hook.where(app_id: APP_ID, status: 'enabled').find do |hook|
      expected = hook.settings['shared_secret'].to_s
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, presented)
    end
  end
end
