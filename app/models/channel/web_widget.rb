# == Schema Information
#
# Table name: channel_web_widgets
#
#  id                    :integer          not null, primary key
#  allowed_domains       :text             default("")
#  continuity_via_email  :boolean          default(TRUE), not null
#  feature_flags         :integer          default(7), not null
#  hmac_mandatory        :boolean          default(FALSE)
#  hmac_token            :string
#  pre_chat_form_enabled :boolean          default(FALSE)
#  pre_chat_form_options :jsonb
#  reply_time            :integer          default("in_a_few_minutes")
#  website_token         :string
#  website_url           :string
#  welcome_tagline       :string
#  welcome_title         :string
#  widget_color          :string           default("#1f93ff")
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer
#
# Indexes
#
#  index_channel_web_widgets_on_hmac_token     (hmac_token) UNIQUE
#  index_channel_web_widgets_on_website_token  (website_token) UNIQUE
#

class Channel::WebWidget < ApplicationRecord
  include Channelable
  include FlagShihTzu

  self.table_name = 'channel_web_widgets'

  # D11 (bloco 0.8): fonte UNICA do default de cor do widget. Antes divergia em
  # tres lugares — a tela cravava o verde da marca (#2dc46f), a coluna e o
  # onboarding cravavam o azul do upstream (#1f93ff) — e a inbox nascia de uma cor
  # ou de outra conforme o caminho de criacao.
  #
  # Default no MODEL e nao na coluna de proposito: `db/schema.rb` conflita em todo
  # merge do upstream, enquanto este arquivo teve 0 mudancas do upstream em quatro
  # minors (v4.12.1 -> v4.16.2, medido na §A.11 do plano 23) — a superficie de
  # merge menor fica aqui. So vale para registro NOVO; nenhuma inbox existente e
  # repintada.
  DEFAULT_WIDGET_COLOR = '#2dc46f'.freeze
  attribute :widget_color, :string, default: DEFAULT_WIDGET_COLOR

  # As sete chaves novas do bloco 3.12 (`step`, `show_if`, `mask`, `validator`,
  # `help_text`, `error_message`, `position`) entram AQUI porque `permit` e lista
  # fechada: chave nao declarada nao levanta erro, e descartada em silencio — o
  # PATCH volta 200 e a mascara simplesmente nao existe no banco. A forma dos
  # VALORES fica em `Channel::WebWidget::PreChatFormSchema`.
  EDITABLE_ATTRS = [:website_url, :widget_color, :welcome_title, :welcome_tagline, :reply_time, :pre_chat_form_enabled,
                    :continuity_via_email, :hmac_mandatory, :allowed_domains,
                    { pre_chat_form_options: [:pre_chat_message, :require_email, :mode,
                                              { pre_chat_fields:
                                                [:field_type, :label, :placeholder, :name, :enabled, :type, :enabled, :required,
                                                 :locale, { values: [] }, :regex_pattern, :regex_cue,
                                                 :step, :position, :mask, :validator, :help_text, :error_message,
                                                 { show_if: [:field, :operator, :value] }] }] },
                    { selected_feature_flags: [] }].freeze

  before_validation :validate_pre_chat_options
  validate :pre_chat_form_options_shape
  validates :website_url, presence: true
  validates :widget_color, presence: true
  has_many :portals, foreign_key: 'channel_web_widget_id', dependent: :nullify, inverse_of: :channel_web_widget

  has_secure_token :website_token
  has_secure_token :hmac_token

  has_flags 1 => :attachments,
            2 => :emoji_picker,
            3 => :end_conversation,
            4 => :use_inbox_avatar_for_bot,
            5 => :allow_mobile_webview,
            :column => 'feature_flags',
            :check_for_column => false

  enum reply_time: { in_a_few_minutes: 0, in_a_few_hours: 1, in_a_day: 2 }

  def name
    'Website'
  end

  # Rótulo do link de contato alternativo (bloco 2.14), no idioma da CONTA — é
  # o idioma em que o site do cliente atende, não o do visitante, porque este
  # texto é gerado no servidor uma vez e colado no HTML dele.
  #
  # `to_json` e não interpolação direta: o rótulo entra dentro de uma string
  # JavaScript, e uma aspa simples vinda da tradução fecharia a string e
  # quebraria o snippet inteiro — justamente o caminho de degradação que este
  # bloco existe para criar.
  def fallback_label_json
    I18n.t(
      'widget.fallback.label',
      locale: account.locale.to_s.to_sym,
      default: I18n.t('widget.fallback.label', locale: :en)
    ).to_json
  end

  # Estilo do link, com a marca do cliente.
  #
  # As cores saem de `WidgetTokens`, a MESMA fonte que pinta o launcher e o
  # painel (bloco 1.02): `brand` já vem sanitizado — `widget_color` é string
  # livre no banco e nada que não case `#RRGGBB` chega à saída — e `on_brand` é
  # o preto ou branco que a WCAG manda usar sobre ela. Recalcular contraste
  # aqui seria a terceira fórmula no projeto, que é o defeito que a Onda 1
  # inteira corrigiu.
  def fallback_style_json
    tokens = WidgetTokens.for(self)
    lado = 'left' # sobrescrito em tempo de execução por `cfg.position`
    [
      'position:fixed;bottom:20px;z-index:2147483000',
      'display:inline-block;padding:12px 20px;border-radius:100px',
      "background:#{tokens.brand};color:#{tokens.on_brand}",
      'font:600 14px/1.2 system-ui,sans-serif;text-decoration:none',
      'box-shadow:0 8px 24px rgba(0,0,0,.16)',
      "#{lado}:20px"
    ].join(';').to_json
  end

  # BLOCO 2.14 — degradação do launcher.
  #
  # O snippet antigo só tinha `g.onload`. Quando o `sdk.js` NÃO carrega —
  # bloqueador de conteúdo, `script-src` da CSP do site do cliente, rede do
  # visitante, CDN fora — nada acontecia: nenhum launcher, nenhum aviso, e o
  # visitante ficava sem canal de contato sem que ninguém ficasse sabendo.
  # `onload` que nunca dispara não é erro para ninguém.
  #
  # A alternativa precisa viver AQUI, no snippet, e não no bundle: é o único
  # código que ainda roda quando o bundle é justamente o que falhou.
  #
  # LIMITE CONHECIDO: quem já colou o snippet antigo no site continua com ele.
  # Não há como alcançar esses sites daqui — o snippet é, por definição, a
  # única parte que o cliente hospeda.
  def web_widget_script
    "
    <script>
      (function(d,t) {
        var BASE_URL=\"#{ENV.fetch('FRONTEND_URL', '')}\";
        var cfg=window.chatwootSettings||{};
#{fallback_bootstrap_js}
#{sdk_loader_js}
      })(document,\"script\");
    </script>
    "
  end

  # A parte que sobrevive ao bundle: define `window.chatwootFallback`, com
  # `show()` e `hide()`. `hide()` é o contrato com `entrypoints/sdk.js`, que o
  # chama ao subir — assim um SDK que chega DEPOIS do prazo retira o link em
  # vez de conviver com ele (o falso positivo do prazo em rede lenta).
  def fallback_bootstrap_js
    "#{fallback_config_js}
#{fallback_functions_js}
        window.chatwootFallback={show:showFallback,hide:hideFallback};"
  end

  # Os quatro valores que o link precisa, todos resolvidos no servidor. Vêm
  # antes das funções porque `showFallback` os fecha por escopo.
  def fallback_config_js
    "        var FALLBACK_URL=cfg.fallbackUrl||BASE_URL+\"/widget?website_token=#{website_token}\";
        var FALLBACK_LABEL=cfg.fallbackLabel||#{fallback_label_json};
        var FALLBACK_STYLE=#{fallback_style_json};
        var LINK_ID=\"cw-fallback-link\";"
  end

  def fallback_functions_js
    '        function showFallback(){
          if(window.$chatwoot||d.getElementById(LINK_ID)||!d.body){return}
          var a=d.createElement("a");
          a.id=LINK_ID;
          a.href=FALLBACK_URL;
          a.target="_blank";
          a.rel="noopener noreferrer";
          a.textContent=FALLBACK_LABEL;
          a.setAttribute("style",cfg.position==="left"?FALLBACK_STYLE:FALLBACK_STYLE.replace("left:20px","right:20px"));
          d.body.appendChild(a)
        }
        function hideFallback(){
          var a=d.getElementById(LINK_ID);
          if(a&&a.parentNode){a.parentNode.removeChild(a)}
        }'
  end

  # O carregamento em si, com os DOIS gatilhos de falha, porque são dois modos
  # distintos:
  #   · `onerror` — o navegador sabe que a requisição falhou (404, DNS, CSP).
  #   · o prazo   — parte dos bloqueadores apenas DESCARTA a requisição, e o
  #                 `script` fica pendente sem falhar nem carregar. Esse é o
  #                 caso mais comum dos dois, e `onerror` não o pega.
  def sdk_loader_js
    "        var g=d.createElement(t),s=d.getElementsByTagName(t)[0];
        g.src=BASE_URL+\"/packs/js/sdk.js\";
        g.async = true;
        s.parentNode.insertBefore(g,s);
        g.onload=function(){
          window.chatwootSDK.run({
            websiteToken: '#{website_token}',
            baseUrl: BASE_URL
          })
        }
        g.onerror=showFallback;
        setTimeout(function(){if(!window.chatwootSDK){showFallback()}},8000);"
  end

  def validate_pre_chat_options
    return if pre_chat_form_options.with_indifferent_access['pre_chat_fields'].present?

    self.pre_chat_form_options = {
      pre_chat_message: 'Share your queries or comments here.',
      pre_chat_fields: [
        {
          'field_type': 'standard', 'label': 'Email Id', 'name': 'emailAddress', 'type': 'email', 'required': true, 'enabled': false
        },
        {
          'field_type': 'standard', 'label': 'Full name', 'name': 'fullName', 'type': 'text', 'required': false, 'enabled': false
        },
        {
          'field_type': 'standard', 'label': 'Phone number', 'name': 'phoneNumber', 'type': 'text', 'required': false, 'enabled': false
        }
      ]
    }
  end

  # Bloco 3.12: a forma de `pre_chat_form_options` conferida por json_schemer.
  # Roda DEPOIS de `validate_pre_chat_options` (que semeia o default de fabrica),
  # de proposito: a semente tambem tem de passar pelo schema.
  def pre_chat_form_options_shape
    options = pre_chat_form_options.presence
    return if options.blank?

    schema_errors = Channel::WebWidget::PreChatFormSchema.validator.validate(options.as_json).to_a
    return if schema_errors.empty?

    # Teto de cinco: um array de oito campos com a mesma chave errada em todos
    # geraria oito mensagens iguais, e a tela mostra o primeiro erro.
    schema_errors.first(5).each do |schema_error|
      errors.add(:pre_chat_form_options, Channel::WebWidget::PreChatFormSchema.humanize(schema_error))
    end
  end

  def create_contact_inbox(additional_attributes = {})
    ::ContactInboxWithContactBuilder.new({
                                           inbox: inbox,
                                           contact_attributes: { additional_attributes: additional_attributes }
                                         }).perform
  end
end
