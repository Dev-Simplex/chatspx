# frozen_string_literal: true

# O lugar da caixa na empresa: o papel dela (texto curto, escrito por quem configura) e se ela
# serve de canal de destino quando a IA leva o cliente para outro canal. Mora em
# `additional_attributes['canal']` e é gravado pela tela de unidades.
#
#   papel             -> o que esta caixa é para a empresa, factual e curto
#   destino           -> a IA pode levar o cliente para esta caixa
#   principal         -> o WhatsApp principal da unidade, usado quando a origem não é WhatsApp
#   template_name     -> template de acionamento aprovado nesta caixa (API oficial)
#   template_language -> idioma desse template
#   texto             -> texto de acionamento no WAHA, que não tem template
#
# Caixa sem nada disso se comporta como hoje: é o padrão de toda conta.
module InboxCanal
  extend ActiveSupport::Concern

  CAMPOS_CANAL = %w[papel destino principal template_name template_language texto].freeze

  included do
    store_accessor :additional_attributes, :canal
    validate :canal_so_em_whatsapp
  end

  def canal_config
    canal.is_a?(Hash) ? canal.slice(*CAMPOS_CANAL) : {}
  end

  def papel
    canal_config['papel'].to_s.strip.presence
  end

  def canal_destino?
    ActiveModel::Type::Boolean.new.cast(canal_config['destino']) || false
  end

  def whatsapp_principal?
    ActiveModel::Type::Boolean.new.cast(canal_config['principal']) || false
  end

  # Caixa que alcança o cliente no WhatsApp: a API oficial ou uma sessão WAHA.
  def fala_whatsapp?
    whatsapp? || (api? && waha_session_name.present?)
  end

  NOMES_DE_CANAL = {
    'Channel::Whatsapp' => 'WhatsApp', 'Channel::Instagram' => 'Instagram', 'Channel::WebWidget' => 'chat do site',
    'Channel::Email' => 'e-mail', 'Channel::Telegram' => 'Telegram', 'Channel::Sms' => 'SMS', 'Channel::Tiktok' => 'TikTok'
  }.freeze

  # Como o cliente chama o canal desta caixa. Página do Facebook com Instagram ligado atende o Instagram.
  def nome_do_canal
    return 'WhatsApp' if fala_whatsapp?
    return 'Instagram' if instagram?
    return 'Messenger' if facebook?

    NOMES_DE_CANAL[channel_type]
  end

  private

  # Destino e principal existem para o acionamento sair por esta caixa — fora do WhatsApp não há
  # por onde mandar.
  def canal_so_em_whatsapp
    return unless canal_destino? || whatsapp_principal?
    return if fala_whatsapp?

    errors.add(:base, I18n.t('errors.units.channel_needs_whatsapp'))
  end
end
