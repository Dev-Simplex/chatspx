# Guia do Desenvolvedor — IA "Elen" da Fábrica dos Óculos (chatspx)

> Guia prático para um dev júnior (usando Claude Code) trabalhar e aperfeiçoar o fluxo da IA **Elen** da Fábrica/Atacadão dos Óculos.
> **Leia também, na ordem:** `.claude/STATE.md` (estado in-flight) · `docs/clientes/fabrica-oculos/FABRICA-OCULOS-PLANO-IA.md` (plano/arquitetura) · nota do cliente no vault `Obsidian/clientes/fabrica-atacadao-oculos.md` (credenciais e infra).
> **Credenciais (SSH, MTM_API_KEY) estão NO VAULT, nunca neste repositório.**

---

## 0. Como usar este guia com o Claude

1. Abra o Claude Code neste diretório (`chatspx`).
2. Peça ao Claude para **ler este guia + o `STATE.md` + a nota do vault** antes de qualquer mudança.
3. Trabalhe em **passos pequenos e verificáveis**: mudou config → teste E2E sintético → leu o resultado → ajustou.
4. **Nunca** invente credenciais; elas estão no vault. **Nunca** comite segredo (MTM key, senha SSH) no repo.

---

## 1. O que é o sistema (visão geral)

A Elen é um **agente nativo do Captain v2** (o motor de IA do Chatwoot, que este fork chama de "Agentes IA"). Ela **substitui um fluxo antigo de n8n** (`auto.spx.ia.br/webhook/elen`, já desligado). Ela atende clientes no WhatsApp, faz triagem (óculos de sol / relógio / óculos de grau), consulta e cadastra o cliente no **CRM próprio (MTM)** por CPF, indica a loja e, no caso de grau sem receita, encaminha para agendar consulta numa clínica parceira (com transporte saindo da loja).

**Duas marcas, um sistema:** Fábrica dos Óculos (Sinop, Sorriso) e Atacadão dos Óculos (Cuiabá, Várzea Grande). No MTM, o campo `departamento` (`fabrica`/`atacadao`) distingue. A cidade define a marca.

---

## 2. Onde tudo vive (o mapa)

| Coisa | Onde |
|---|---|
| **Servidor (prod/teste)** | `ssh chatwoot@3.87.182.184` (host `ip-172-31-83-31`), URL `https://fabrica.chatspx.app`. App em `/home/chatwoot/chatwoot`, branch `producao` (clone do esqueleto Tozi). Ruby 3.4.4. Postgres `chatwoot_production`. |
| **Conta** | Account **1** = "Fábrica dos Óculos" (a Elen vive aqui; os 8 shops das DUAS marcas estão no mesmo MTM). Account 2 = "Atacadão" (vazio por ora). |
| **A IA** | `Captain::Assistant #1` ("Elen") + espelho `AgentBot #1` (`bot_type: captain`). |
| **Inbox do WhatsApp** | Inbox **2** (`Channel::Api`, "Fabrica") — sessão WAHA. (Inbox 1 = WebWidget do site.) |
| **Ligação IA↔inbox** | `CaptainInbox(inbox_id: 2, captain_assistant_id: 1)` = ELEGIBILIDADE. + `AutomationRule #1` (`conversation_created` → `assign_ai_agent([1])`, cond `inbox_id=2`) = GATILHO de entrada. |
| **Tools MTM** | 4 `Captain::CustomTool` na Account 1: `mtm_buscar_cliente`, `mtm_registrar_cliente`, `mtm_loja_por_cidade`, `mtm_listar_clinicas`. |
| **LLM** | Modelo `gpt-5-mini` (`account.captain_models['assistant']`). Chave em `InstallationConfig['CAPTAIN_OPEN_AI_API_KEY']`. |
| **CRM/ERP** | **MTM** (REST, Bearer) — `https://fabrica.simplexsolucoes.com.br/api/v1`, doc em `/api-docs`. ERP por trás = Acert. |
| **Scripts de referência** | `Temp/setup_mtm_tools.rb`, `Temp/setup_elen_brain.rb`, `Temp/elen_ligar.rb`, `Temp/elen_e2e.rb`. |

---

## 3. Como a IA responde (o pipeline)

```
Cliente manda WhatsApp
  -> mensagem entra na inbox 2 (Channel::Api)
  -> SE conversa NOVA: AutomationRule #1 (conversation_created) chama assign_ai_agent([1])
        -> action_service confere ELEGIBILIDADE (CaptainInbox) -> seta assignee_agent_bot_id = espelho da Elen
  -> incoming numa conversa já atribuída à Elen enfileira Captain::Conversation::DebouncedResponseJob (debounce 9s)
  -> Captain::Conversation::ResponseBuilderJob:
        gate captain_can_respond? (status open/pending E assignee_agent_bot_id == espelho da Elen)
        -> Captain::Assistant::AgentRunnerService (captain_v2) -> LLM gpt-5-mini + tools
        -> resposta vem como JSON {"response": "...", "reasoning": "..."}
        -> se response == 'conversation_handoff' -> handoff (dossiê + time + marcador aguardando_humano)
        -> senão -> HumanizerService quebra em bolhas -> cria mensagens outgoing (com "digitando")
```

**Arquivos-chave (ler antes de mexer):**
- `enterprise/app/jobs/captain/conversation/response_builder_job.rb` — orquestra a resposta, humanizer, handoff, `sanitize_for_whatsapp`.
- `enterprise/app/services/captain/assistant/agent_runner_service.rb` — roda o agente (LLM + tools).
- `enterprise/app/services/enterprise/action_service.rb` — `assign_ai_agent` (gate de elegibilidade na linha ~26).
- `enterprise/app/models/captain/assistant.rb` — modelo da Elen (`config`, `behavior`, `configured_agent_tools`).
- `enterprise/app/models/captain/custom_tool.rb` + `enterprise/app/models/concerns/toolable.rb` + `enterprise/lib/captain/tools/http_tool.rb` — como custom tool vira chamada HTTP.
- `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb` — reentrada em conversa órfã (`orphan_captain_reentry?`, baseada em time).

---

## 4. Acessar o servidor e rodar Ruby (a receita)

> **Por que essa firula:** o Windows/Git Bash corrompe acentos em heredoc, e o SSH precisa de senha não-interativa. Solução: `SSH_ASKPASS` + transferir scripts por **base64**.

**Padrão (de dentro do `chatspx`, no Git Bash):**
```bash
TMP=$(mktemp -d); printf '#!/bin/sh\necho "<SENHA_SSH_DO_VAULT>"\n' > "$TMP/ap.sh"; chmod +x "$TMP/ap.sh"
B64=$(base64 -w0 Temp/meu_script.rb)        # script Ruby escrito com o Write (UTF-8)
{ echo "cat > /tmp/x.b64 <<'EOF'"; echo "$B64"; echo "EOF";
  echo "base64 -d /tmp/x.b64 > /tmp/x.rb";
  echo "bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner /tmp/x.rb'";
  echo "rm -f /tmp/x.b64 /tmp/x.rb"; } > "$TMP/remote.sh"
SSH_ASKPASS="$TMP/ap.sh" SSH_ASKPASS_REQUIRE=force \
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null chatwoot@3.87.182.184 'bash -s' < "$TMP/remote.sh"
rm -rf "$TMP"
```
Regras:
- **Sempre escreva o script Ruby com a tool Write (UTF-8)** e transfira por base64. Não cole Ruby acentuado em heredoc inline.
- Segredos (MTM key) entram via `ENV` no comando, **nunca** hardcoded no arquivo do repo.
- `bash -lc` é obrigatório (carrega o RVM/Ruby).

---

## 5. Como mexer no COMPORTAMENTO da Elen

Tudo é **config no banco** (sem deploy de código). O molde é `Temp/setup_elen_brain.rb`.

### 5.1 O prompt (persona/regras)
`Captain::Assistant.find(1).config['instructions']` — string única em PT-BR. É AQUI que se ajusta tom, regras, fluxos e limites. Edite o script local, transfira, rode. Verifique: `puts a.config['instructions'].length`.

### 5.2 As tools que a Elen pode usar
`config['tools']` = array de slugs (ex: `["mtm_buscar_cliente", ...]`). `handoff`, `faq_lookup`, `search_knowledge` vêm por padrão (não precisam estar na lista).

### 5.3 Behavior (debounce, humanizer, horário)
`Captain::Assistant.find(1).behavior` (JSONB). Campos: `debounce_seconds`, `humanizer` (`max_chars`, `delay_ms`, `min_delay_s`...), `business_hours`, `dedup`, `router`. **Não mexa sem necessidade** — está calibrado.
- O **horário comercial** hoje é global. A loja Shopping fura (10h-22h + domingo) — fazer por loja é trabalho futuro.

### 5.4 Modelo / velocidade
`Account.find(1).captain_models` → `{'assistant' => 'gpt-5-mini', 'editor' => 'gpt-4.1-mini'}`. Trocar o modelo **não exige restart** (lido por request). Trocar a CHAVE exige restart (§7).

---

## 6. As tools MTM (como funcionam e como criar novas)

São `Captain::CustomTool` (config no banco, **sem deploy**). Contrato (ver `concerns/toolable.rb` + `http_tool.rb`):
- `endpoint_url` é **template Liquid** (`.../clients?cpf={{ cpf | url_encode }}`). Só GET e POST.
- `request_template` (POST) é Liquid → corpo JSON.
- `response_template` é Liquid sobre o JSON parseado, com contexto `r` (= resposta). Ex: `{% for s in r.data %}{{ s.nome }}{% endfor %}`.
- `auth_type: 'bearer'`, `auth_config: { 'token' => <MTM_API_KEY> }`.
- `param_schema`: array de `{name, type, description, required}`.

**Gotchas (que já custaram tempo):**
- ⚠️ **Acento na query do `endpoint_url` quebra** (`URI must be ascii only`) → use o filtro `| url_encode` nos params da URL.
- ⚠️ **Liquid é strict** (`strict_variables`): se o template referencia uma variável não passada, a tool retorna erro genérico. Por isso, params usados no template = `required: true` (a IA passa `""` quando não sabe).
- O executor bloqueia IP privado (anti-SSRF) e limita resposta a 1MB.

Molde completo: `Temp/setup_mtm_tools.rb` (idempotente, com auto-teste das tools GET).

---

## 7. Gotchas críticos de operação

| Gotcha | Detalhe |
|---|---|
| **Chave de LLM exige RESTART** | `config/initializers/ai_agents.rb` lê `CAPTAIN_OPEN_AI_API_KEY` no boot. Mudou a chave → restart. (Mudar modelo não.) |
| **Como reiniciar** | `sudo systemctl restart chatwoot.target` (o user `chatwoot` tem NOPASSWD **só pro target**, não pros units `chatwoot-web.1`/`worker.1`). |
| **SEMPRE `migrate:status` antes do restart** | `RAILS_ENV=production bundle exec rails db:migrate:status` → 0 `down` = seguro. Migration pendente + restart = 500 em cadeia. |
| **Texto PT no servidor** | Escreva com Write (UTF-8) + base64. Heredoc no Git Bash corrompe acento. |
| **Cliente que VOLTA não aciona a Elen** | A regra é `conversation_created`. Conversa que já existe (reaberta por `lock_to_single`) ou as abertas atuais NÃO disparam. Falta gatilho por `message_created` (ver Backlog). |
| **Webhook do n8n ainda cadastrado** | `Webhook #1` (`auto.spx.ia.br/webhook/elen`) segue no Chatwoot mas o n8n está off (endpoint morto). Limpeza opcional. |
| **Sem whitelist** | A Elen responde QUALQUER conversa nova na inbox 2 (VM em teste). Cuidado ao apontar pra produção real. |

---

## 8. Como TESTAR (sem mandar WhatsApp real)

Dois caminhos (moldes em `Temp/`):

**A) Síncrono (rápido, isola a IA)** — `Temp/elen_e2e.rb`: cria contato+conversa, atribui o espelho da Elen, cria 1 incoming e chama `Captain::Conversation::ResponseBuilderJob.perform_now(conv, assistant)`. Lê as bolhas geradas. Bom pra iterar prompt/tool.

**B) Automático (caminho real)** — `Temp/elen_ligar.rb`: cria conversa NOVA **sem** atribuir, espera ~50s e confere se a regra atribuiu a Elen e ela respondeu. Prova o fluxo de ponta a ponta.

**Inspecionar uma conversa real:** dump por `display_id` (transcrição + `Captain::AssistantLog`) — veja o script da análise da conv 307 (eventos: `mirror_assigned`, `debounce_fire`, `humanizer_split`).

> Limpe as conversas de teste depois (resolve ou destroy), e cuidado: `destroy!` é irreversível.

---

## 9. Backlog de COMPORTAMENTO a corrigir (da conv 307)

Prioridade alta (são fixes de PROMPT, em `config['instructions']`):
1. **Parar de repetir o aviso de "fora do horário comercial".** Na 307 ela repetiu 4×. Regra: dizer no MÁXIMO 1×, e só se for relevante.
2. **Parar de re-explicar o mesmo fluxo.** Ela explicou o fluxo "sem receita" 2× e relistou as lojas 2×. Dizer uma vez.
3. **Menos bolhas / mais concisa.** 3-4 bolhas por turno repetindo info. Reforçar "frases curtas, responda só o que foi perguntado".
4. **NÃO pedir pro cliente escolher a loja de uma lista.** Regra de negócio: a IA escolhe a mais próxima, não oferece menu. Na 307 ela listou e perguntou "qual?" várias vezes.
5. **NÃO fingir que calculou a "loja mais próxima".** Ela disse "escolhi André Maggi como a mais próxima do Residencial Paris" — mas **não tem ferramenta de proximidade** (o MTM `/shops` não tem lat/lng). Ou (a) construir a tool `loja_mais_proxima` (mapa estático de lat/lng das 8 lojas + Haversine, ou mapa bairro→loja), ou (b) instruir a Elen a não afirmar proximidade que não consegue calcular.
6. **Não terminar toda mensagem com pergunta** (ela fechou com "Precisa de mais alguma coisa?").
7. **Usar o número do WhatsApp** do contato em vez de pedir o telefone (o `phone_number` do contato já é o número dele).
8. **Auto-apresentação por marca:** para cliente de Sinop, dizer só "Fábrica dos Óculos" (não as duas marcas).

Operacional/observado:
9. Artefato "Conversa desatribuída por Sistema de Automação" logo após a atribuição (investigar; provável transiente do fluxo de assign).
10. O handoff atribui ao **time da loja** (ex: "sinop - andre maggi"), mas esses times **não têm membros humanos** → o "aguardando humano" fica parado. Garantir membros nos times ou repensar o destino do handoff.

---

## 10. Backlog de FEATURES (precisa de dados/decisão do cliente)

| Item | Bloqueio |
|---|---|
| **`loja_mais_proxima` (tool nova, código)** | MTM `/shops` sem lat/lng. Manter mapa estático de coords das 8 lojas (ids 2-9) + Haversine; usar pin do cliente ou geocodar bairro/CEP. Molde: `enviar_localizacao_tool.rb`/`buscar_imovel_tool.rb` (Haversine). |
| **`agendar` (tool, POST /appointments)** | O MTM exige `seller_id` e só existe 1 vendedor (Ana Carla #8). Definir o vendedor que a IA usa. Usar `appointment_origin_id = 42` ("WhatsApp - Bot Elen", hoje inativa — reativar). `clinic_id` presente = consulta; ausente = visita. |
| **Broker de clínica** | As 17 clínicas estão **sem `contato_whatsapp_e164`** no MTM. Preencher para a IA conseguir mandar a proposta. Subsistema de proposta (Aceitar/Sugerir/Recusar) a construir. |
| **Gatilho cliente-que-volta** | Adicionar regra/handler por `message_created` (com guarda de "sem humano") OU mapear Elen a times pra usar `orphan_captain_reentry?`. |
| **Horário por loja** | Hoje global. Shopping (10h-22h + domingo) precisa de exceção por loja. |

---

## 11. Referência rápida da API MTM

- Base: `https://fabrica.simplexsolucoes.com.br/api/v1` · Doc: `/api-docs` · Auth: `Authorization: Bearer <MTM_API_KEY>` (no vault).
- `GET /clients?cpf=` — busca por CPF (campos: `razao_social`, `cpf`, `fone1`, `cidade`, `bairro`, `status`…).
- `POST /clients` — cadastra lead.
- `GET /shops?departamento=&cidade=` — lojas (ids 2-9; **sem lat/lng**). departamento = `fabrica`/`atacadao`.
- `GET /clinics?ativo=true` — clínicas (têm `valor_consulta`, `contato_whatsapp_e164` [hoje null], `lat/lng`, `sla_resposta_min`).
- `POST /appointments` — agendamento (`time`,`shop_id`,`seller_id` obrigatórios; `clinic_id`,`proposal_id` opc.).
- Também: `/sellers`, `/appointment-origins`, `/checkups`, `/vision-tests`, `/products`, `/stocks` (Acert, read-only).

---

## 12. Princípios ao aperfeiçoar

- **Constante institucional vai no PROMPT, não no RAG** (endereço, horário, como funciona o serviço). Dado dinâmico (cliente, loja, clínica) vem das TOOLS.
- **Mude uma coisa, teste, leia o resultado.** Use o teste síncrono pra iterar prompt rápido.
- **Não declare capacidade que a IA não tem** (ex: proximidade sem tool). Ou construa a tool, ou ajuste o prompt pra ela não fingir.
- **Cada fix de comportamento = ajuste no `instructions`** + reteste. Não precisa restart (config é lida por request; só a CHAVE precisa de restart).
