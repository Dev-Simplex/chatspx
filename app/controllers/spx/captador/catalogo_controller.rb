# Catálogo para o formulário de envio e a tela Conexões do Captador (22 §1.6).
#
# Só o que o Captador usa. Substitui o GET /inboxes com token de admin, que devolve provider_config
# (o token da WABA) e hmac_token: nada disso sai daqui. Lista as caixas de WhatsApp da conta,
# oficiais (Cloud, com os modelos aprovados) e não oficiais (API/WAHA, texto livre), marcando as que
# o hook libera; o Captador mostra as outras como "não liberadas" em vez de escondê-las.
class Spx::Captador::CatalogoController < Spx::Captador::BaseController
  CHANNEL_TYPES = %w[Channel::Whatsapp Channel::Api].freeze
  TEMPLATE_FIELDS = %w[name language category components parameter_format].freeze

  def show
    inboxes = @account.inboxes.where(channel_type: CHANNEL_TYPES).includes(:channel).order(:id).to_a
    render json: {
      account: { id: @account.id, name: @account.name },
      inboxes: inboxes.map { |inbox| inbox_json(inbox) },
      teams: @account.teams.order(:id).map { |team| { id: team.id, name: team.name } },
      agents: agents_json(inboxes.map(&:id))
    }
  end

  private

  def inbox_json(inbox)
    official = inbox.whatsapp?
    {
      id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, official: official, provider: provider(inbox),
      phone_number: official ? inbox.channel.phone_number : nil, read_only: inbox.read_only?,
      allowed: allowed_inbox_ids.include?(inbox.id.to_s), templates: official ? approved_templates(inbox) : []
    }
  end

  def provider(inbox)
    return inbox.channel.provider if inbox.whatsapp?

    inbox.waha_session_name.present? ? 'waha' : 'api'
  end

  def allowed_inbox_ids
    @allowed_inbox_ids ||= @hook.settings['allowed_inbox_ids'].to_s.split(',').map(&:strip)
  end

  def approved_templates(inbox)
    Array(inbox.channel.message_templates)
      .select { |template| template['status'].to_s.casecmp?('approved') }
      .map { |template| template.slice(*TEMPLATE_FIELDS) }
  end

  # inbox_ids diz por quais caixas a pessoa pode enviar (o POST leads recusa as outras com 403):
  # administrador, todas; agente, as de que é membro.
  def agents_json(inbox_ids)
    memberships = InboxMember.where(inbox_id: inbox_ids).pluck(:user_id, :inbox_id)
                             .group_by(&:first).transform_values { |pairs| pairs.map(&:last).sort }
    @account.account_users.includes(:user).order(:user_id).map do |account_user|
      user = account_user.user
      {
        id: user.id, name: user.name, available_name: user.available_name, email: user.email, role: account_user.role,
        inbox_ids: account_user.administrator? ? inbox_ids : memberships.fetch(user.id, [])
      }
    end
  end
end
