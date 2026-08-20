module AccountSettingsSchema
  extend ActiveSupport::Concern

  CAPTAIN_MODEL_PROPERTIES = Llm::Models.feature_keys.index_with { { 'type': %w[string null] } }.freeze
  CAPTAIN_FEATURE_PROPERTIES = Llm::Models.feature_keys.index_with { { 'type': %w[boolean null] } }.freeze

  SETTINGS_PARAMS_SCHEMA = {
    'type': 'object',
    'properties':
      {
        'auto_resolve_after': { 'type': %w[integer null], 'minimum': 10, 'maximum': 1_439_856 },
        'auto_resolve_message': { 'type': %w[string null] },
        'auto_resolve_ignore_waiting': { 'type': %w[boolean null] },
        'audio_transcriptions': { 'type': %w[boolean null] },
        'auto_resolve_label': { 'type': %w[string null] },
        'keep_pending_on_bot_failure': { 'type': %w[boolean null] },
        'resolve_assignment_gate': { 'type': %w[boolean null] },
        'takeover_request_gate': { 'type': %w[boolean null] },
        'captain_auto_resolve_mode': { 'type': %w[string null], 'enum': ['evaluated', 'legacy', 'disabled', nil] },
        'captain_false_promise_harness_enabled': { 'type': %w[boolean null] },
        'reply_assignment_gate': { 'type': %w[boolean null] },
        'orphan_retriage_after': { 'type': %w[integer null], 'minimum': 5, 'maximum': 10_080 },
        'conversation_required_attributes': {
          'type': %w[array null],
          'items': { 'type': 'string' }
        },
        # ── RECONCILIACAO homologacao × v4.16.2 ────────────────────────────────────────────
        #
        # Estas duas chaves vieram do `SETTINGS_PARAMS_SCHEMA` que vivia INLINE em
        # `account.rb` na homologacao. O upstream extraiu o schema para este concern e, no
        # merge, o lado dele nao as tinha — sao features da equipe, nao do upstream.
        #
        # Resolver `account.rb` a favor do concern SEM traze-las teria apagado as duas em
        # silencio: `additionalProperties: true` deixa o valor ser GRAVADO, mas sem a
        # declaracao o campo perde validacao de tipo e some de qualquer consumidor que leia o
        # schema. O sintoma apareceria semanas depois, no roteamento de template ou no convite
        # de contato de um cliente.
        'template_reply_routing': {
          'type': %w[object null],
          'properties': {
            'enabled': { 'type': %w[boolean null] },
            'rmkt_label_prefix': { 'type': %w[string null] },
            'rmkt_assistant_id': { 'type': %w[integer null] }
          },
          'additionalProperties': false
        },
        'contact_invite': {
          'type': %w[object null],
          'properties': {
            'enabled': { 'type': %w[boolean null] },
            'template_name': { 'type': %w[string null] },
            'referral_template_name': { 'type': %w[string null] },
            'language': { 'type': %w[string null] },
            'cooldown_hours': { 'type': %w[integer null], 'minimum': 1, 'maximum': 720 },
            'referral_label': { 'type': %w[string null] }
          },
          'additionalProperties': false
        },
        'captain_models': {
          'type': %w[object null],
          'properties': CAPTAIN_MODEL_PROPERTIES,
          'additionalProperties': false
        },
        'captain_features': {
          'type': %w[object null],
          'properties': CAPTAIN_FEATURE_PROPERTIES,
          'additionalProperties': false
        }
      },
    'required': [],
    'additionalProperties': true
  }.to_json.freeze
end
