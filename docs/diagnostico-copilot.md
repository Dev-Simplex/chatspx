# Diagnóstico: Copilot não está funcionando

Este documento descreve como diagnosticar e corrigir problemas com o Copilot do Chatwoot.

## Ferramentas de diagnóstico

### 1. Rake task de diagnóstico

Execute o diagnóstico para uma conta:

```bash
bundle exec rake captain:diagnose[ACCOUNT_ID]
```

Exemplo para conta 3:

```bash
bundle exec rake captain:diagnose[3]
```

O comando verifica:
- Feature flags (captain_integration, captain_integration_v2)
- Chave API OpenAI configurada
- Assistentes disponíveis
- Limite de créditos de respostas
- Hook OpenAI

### 2. Habilitar features do Captain

Se o diagnóstico indicar que os features estão desabilitados:

```bash
bundle exec rake captain:enable_features[ACCOUNT_ID]
```

Ou no Rails console:

```ruby
Account.find(ACCOUNT_ID).enable_features!('captain_integration', 'captain_integration_v2')
```

### 3. Script de teste curl

Use o script para testar a API diretamente:

```bash
./script/copilot_curl_test.sh <BASE_URL> <ACCOUNT_ID> <ASSISTANT_ID> <CONVERSATION_ID> <ACCESS_TOKEN> <CLIENT> <USER_UID>
```

Exemplo:

```bash
./script/copilot_curl_test.sh https://chatspx.app 3 2 461 "seu-access-token" "seu-client" "user@example.com"
```

Ou exporte as variáveis de ambiente:

```bash
export COPILOT_BASE_URL=https://chatspx.app
export COPILOT_ACCOUNT_ID=3
export COPILOT_ASSISTANT_ID=2
export COPILOT_CONVERSATION_ID=461
export COPILOT_ACCESS_TOKEN=seu-token
export COPILOT_CLIENT=seu-client
export COPILOT_UID=user@example.com
./script/copilot_curl_test.sh
```

## Pontos de falha comuns

| Erro HTTP | Causa | Solução |
|-----------|-------|---------|
| 401 | Token expirado ou inválido | Fazer login novamente e obter novos headers (access-token, client, uid) |
| 404 | Assistente não encontrado | Verificar se o assistant_id existe na conta: `Account.find(ID).captain_assistants.pluck(:id)` |
| 422 | Chave API OpenAI ausente | Configurar em: Configurações > Integrações > OpenAI |
| 200 mas sem resposta | Limite de créditos esgotado | Verificar `usage_limits[:captain][:responses]` e comprar créditos |
| 200 mas sem resposta | Job assíncrono falhou | Verificar logs do Sidekiq e buscar por `Captain::Copilot::ResponseJob` |

## Verificações manuais (Rails console)

```ruby
account = Account.find(3)

# Features habilitados?
account.feature_enabled?('captain_integration')
account.feature_enabled?('captain_integration_v2')

# API Key configurada?
Captain::OpenaiHookService.new(account: account).configured?

# Assistentes disponíveis
account.captain_assistants.pluck(:id, :name)

# Limites de uso
account.usage_limits[:captain][:responses]
```

## Arquivos relevantes

- Controller: `enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb`
- Job: `enterprise/app/jobs/captain/copilot/response_job.rb`
- Validação API key: `app/controllers/concerns/captain/api_key_validation.rb`
- Limites: `enterprise/app/models/enterprise/account/plan_usage_and_limits.rb`
