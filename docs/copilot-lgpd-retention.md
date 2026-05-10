# Copilot ChatSPX — Política de privacidade, LGPD e retenção

**Versão:** 1.0
**Data:** 2026-04-30
**Escopo:** funcionalidades de IA do Copilot (rewrite, summarize, reply suggestion, sentiment, follow-up)

---

## 1. Quais dados o Copilot processa

| Dado | Origem | Tratamento |
|------|--------|------------|
| Conteúdo da mensagem do agente (rascunho) | Composer no Dashboard | Sanitizado (PII) → enviado ao provedor LLM (OpenAI ou self-hosted) |
| Mensagens públicas da conversa (`private: false`) | DB Chatwoot | Sanitizadas (PII) → enviadas ao provedor LLM |
| Nome do contato e canal | DB Chatwoot | Pode aparecer em prompts (ex: contexto de "improve") |
| Histórico de follow-up (refinamentos do agente) | Memória de sessão por requisição | Sanitizado (PII) → enviado ao LLM em cada follow-up |

**O que NÃO é enviado ao LLM:**
- Mensagens marcadas como privadas (`private: true`) — filtradas no `BaseTaskService#conversation_messages` e em `SentimentAnalysisService` via cláusula `where(private: false)`.
- Anexos binários (imagens, áudio, PDF) — só texto.
- Credenciais, tokens, API keys.

---

## 2. Defense-in-depth de PII

A sanitização ocorre em **duas camadas**:

### Camada 1 — Frontend (`app/javascript/dashboard/components-next/ai-assistant/utils/sanitizePII.js`)
- Aplicada antes do request HTTP ao Captain
- Padrões mascarados por padrão: **CPF**, **CNPJ**, **telefone BR**, **cartão de crédito** (com validação Luhn)
- Padrões opt-in: **email**, **CEP**
- Telemetria: emite `useTrack('ai.pii.redacted', { count, types, event })` quando algo é redatado

### Camada 2 — Backend (`lib/captain/pii_sanitizer.rb` → `Captain::PiiSanitizer`)
- Aplicada nos services antes da injeção no Liquid template / mensagem do LLM
- Mesmos padrões + Luhn check em cartão
- Reaplicada em `SummaryService`, `ReplySuggestionService`, `FollowUpService`, `RewriteService` (improve/shorten/expand), `SentimentAnalysisService`

**Por que duas camadas?** Se o frontend é bypassed (ex: chamada direta à API por integração custom), o backend ainda mascara antes de mandar para a OpenAI.

---

## 3. Modo privado — bloqueio explícito

Quando o agente está com o composer em **modo NOTE (nota privada)**:

- **Frontend** (`useCaptain#processEvent`): bloqueia operações de rewrite (`improve`, tone changes, `shorten`, `expand`, `fix_spelling_grammar`, `sentiment`) com toast "Modo privado: IA desativada para evitar vazamento da nota interna" e telemetria `ai.private_mode.blocked`.
- **Backend**: serviços que leem mensagens da conversa filtram `where(private: false)` antes de injetar no LLM. Notas privadas nunca atingem o provedor.

---

## 4. Retenção de histórico

| Tipo | Retenção | Onde |
|------|----------|------|
| Histórico de "ask Copilot" (threads `copilot_threads` + `copilot_messages`) | 90 dias | Tabelas `copilot_threads`, `copilot_messages` no Postgres |
| Follow-up context | Em memória da sessão do agente (volátil) | `useCopilotReply.followUpContext` ref |
| Telemetria (`ai.captain.responded`, `ai.pii.redacted`, etc.) | 30 dias | Pipeline de analytics interno |
| Logs do provedor LLM (OpenAI) | Conforme política do provedor (atualmente 30 dias para zero data retention orgs) | OpenAI |

A retenção de 90 dias para `copilot_threads` alinha com a política geral de retenção de mensagens do Chatwoot. Limpeza ativa via job a ser implementado em fase futura.

---

## 5. Kill-switch

A IA pode ser desativada **sem deploy** através da feature flag `ai_assistant_v2`:

1. **Server-side (super-admin):** desliga a flag em `accounts.feature_flags` — bloqueia o uso do painel v2 para a conta inteira.
2. **Client-side (canary):** o agente individual pode setar `localStorage.chatspx_ai_panel_v2 = 'off'` ou abrir a URL com `?aiv2=0` (persiste em `sessionStorage`) para opt-out manual.

A flag `ai_assistant_v2` está cadastrada em `config/features.yml` com `enabled: false` por padrão e `chatwoot_internal: false` para permitir toggle via UI do super-admin.

---

## 6. Direitos do titular (LGPD)

| Direito (LGPD Art. 18) | Como atendemos |
|------------------------|----------------|
| Confirmação de tratamento | Cliente pode pedir relatório das interações via super-admin (logs em `copilot_messages`) |
| Acesso aos dados | Export do histórico IA via super-admin (mecanismo manual hoje, automatizado em fase futura) |
| Correção | Solicitação manual por chamado interno |
| Anonimização / eliminação | Hard delete em `copilot_threads` + `copilot_messages` por requisição |
| Portabilidade | Export CSV/JSON via super-admin |
| Oposição | Desativação da feature flag bloqueia processamento futuro |

**Contato DPO:** dpo@simplexsolucoes.com.br

---

## 7. Subprocessadores

| Provedor | Dados compartilhados | Localização | Base legal |
|----------|---------------------|-------------|------------|
| OpenAI (ou substituto self-hosted) | Conteúdo de mensagens públicas, sanitizado | EUA | Execução de contrato (LGPD Art. 7º, V) |

Caso a configuração `CAPTAIN_OPEN_AI_ENDPOINT` aponte para um endpoint self-hosted (ex: vLLM em VPS própria), a transferência internacional **não se aplica**.

---

## 8. Auditoria

- Toda chamada ao Copilot é instrumentada via `Integrations::LlmInstrumentation` (Langfuse) com `account_id`, `conversation_id`, `feature_name`, latência, tokens.
- Em caso de redação de PII, a telemetria registra contagem e tipos (sem o conteúdo original).

---

## 9. Roadmap de hardening pendente

- [ ] Job recorrente de purga `copilot_threads` >90 dias
- [ ] UI de export de histórico IA na área do super-admin
- [ ] Banner informativo no primeiro uso do painel: "Suas mensagens vão para um provedor de IA. Saiba mais → /privacy"
- [ ] Allowlist de regiões de export (compliance regional)
- [ ] Anonimização automática do nome do contato em logs (já mascaramos PII, mas não nome próprio)
