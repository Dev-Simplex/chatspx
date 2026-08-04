# Traduz o payload do formulario do site para o formato de lead que a engine
# compartilhada consome, e entrega. Tudo que e especifico do site vive AQUI — a engine
# (Meta::LeadAds::CreateConversationService) segue generica, do mesmo jeito que tudo que
# e especifico da Meta vive no Webhooks::MetaLeadAdsJob e nao no servico.
class Webhooks::SiteLeadJob < ApplicationJob
  queue_as :default

  # Como o lead aparece pro time no painel e no corte por campanha.
  ORIGEM = 'Site'.freeze

  def perform(hook_id, payload)
    hook = Integrations::Hook.find_by(id: hook_id)
    return Rails.logger.warn("Site Leads: hook #{hook_id} não encontrado — lead descartado") if hook.nil?

    Meta::LeadAds::CreateConversationService.new(hook: hook, lead: lead_from(payload)).perform
  rescue StandardError => e
    # Re-raise pro Sidekiq: o retry e o que salva o lead quando o Vista ou a Meta oscilam.
    # O servico e idempotente (reusa a conversa e nao reenvia a abertura), entao repetir e seguro.
    Rails.logger.error("Site Leads: falha processando lead do hook=#{hook_id}: #{e.class}: #{e.message}")
    raise
  end

  private

  def lead_from(payload)
    {
      leadgen_id: lead_id(payload),
      full_name: payload['nome'],
      phone_number: payload['telefone'],
      email: payload['email'],
      # O codigo do imovel da pagina em que a pessoa estava e o MESMO dado que o
      # retailer_item_id dos anuncios de catalogo: o codigo do imovel no Vista. Reusando
      # a chave, a busca do imovel (descricao + foto de destaque), o carimbo
      # meta_imovel_codigo/meta_imovel e o opener com foto saem de graca — e a conduta
      # que ja sabe abrir no "imovel do anuncio" funciona sem uma linha nova.
      retailer_item_id: payload['codigo_imovel'],
      jornada: payload['jornada'],
      campaign_name: ORIGEM,
      platform: ORIGEM
    }.compact
  end

  # Id estavel por telefone: a mesma pessoa reenviando o formulario cai no mesmo id, o
  # que mantem o rastro nos logs coerente. A idempotencia de verdade nao depende disto
  # (o servico reusa a conversa do contato e nao reenvia a abertura).
  def lead_id(payload)
    "site:#{payload['telefone'].to_s.gsub(/\D/, '')}"
  end
end
