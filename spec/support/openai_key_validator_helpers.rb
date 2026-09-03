# ChatSPX (item 25): o upstream v4.16.2 passou a validar a chave OpenAI por HTTP SÍNCRONO dentro do
# save do Integrations::Hook (`validate :validate_openai_api_key`, hook.rb:32). Consequência na
# suíte: todo spec que cria um hook de openai — direta ou indiretamente, por factory — tenta um
# `GET https://api.openai.com/v1/models` e morre em WebMock::NetConnectNotAllowedError.
#
# Medição do executor da DoD: **51 falhas** por essa causa no merge, contra **0** no baseline
# `f26db6ee81` (mesmos specs, mesmo ambiente, banco próprio) — logo é do merge, não do ambiente.
#
# A causa em produção está corrigida em lib/integrations/openai/key_validator.rb (item 24:
# fail-open no 401 quando há endpoint customizado). Aqui só se impede que a suíte faça chamada de
# rede real: o default passa a ser "chave válida", que é o que praticamente todo spec pressupõe.
#
# Como escapar deste default, quando o spec É sobre a validação:
#   · specs de `Integrations::Openai::KeyValidator` são detectados e deixados em paz (eles stubbam
#     a rede com WebMock e asseveram o contrato do validador);
#   · qualquer spec pode declarar `real_openai_key_validation: true` na metadata;
#   · e um `allow(...).to receive(:valid?)` no próprio exemplo continua vencendo este default,
#     porque hooks de grupo rodam depois dos hooks globais (é o que spec/models/integrations/
#     hook_spec.rb já faz, e ele segue valendo).
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:real_openai_key_validation]
    next if example.metadata[:described_class] == Integrations::Openai::KeyValidator

    # `key.present?` e não `true`: o único veredito que o validador real dá SEM tocar a rede é
    # "chave em branco é inválida" (`return false if api_key.blank?`), e há spec que depende dele
    # (spec/models/integrations/hook_spec.rb:127). Só a parte que faria HTTP é substituída.
    allow(Integrations::Openai::KeyValidator).to receive(:valid?, &:present?)
  end
end
