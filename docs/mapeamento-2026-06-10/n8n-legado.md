# Mapeamento — Legado n8n da Clara (Tozi) e estado da migração pro Captain v2

> Área: **n8n-legado** · Gerado em 2026-06-10 · Workspace analisado: `C:/Users/paulo/Workspaces/tozi` (fora do repo) + comparação com `C:/Users/paulo/Workspaces/chatspx` (branch paulao).
> Tudo baseado em leitura real dos arquivos; referências `arquivo:linha` ao longo do texto.

---

## 0. Fontes encontradas

| Arquivo | Conteúdo |
|---|---|
| `tozi/Tozi SDR - Atendimento e Copiloto.json` (108 KB, 60 nodes) | Workflow principal n8n exportado — Clara, Copiloto, mídia, roteamento |
| `tozi/subworkflows/Tozi TOOL - Buscar imóveis.json` | Subworkflow tool Vista CRM (4 nodes) — único subworkflow em disco |
| `tozi/README.md` | Visão geral, arquitetura, rotas, documentação dos 3 subworkflows (Atribuir Atendimento e Buscar Localização documentados mas **não exportados** em disco) |
| `tozi/prompts/` | `prompt-clara.md`, `prompt-atribuidor.md`, `prompt-copiloto.md`, `prompt-humanizador.md`, `prompt-vision-imagem.md`, `tools-descricoes.md` |
| `tozi/BACKLOG.md` | Roadmap n8n nunca implementado (follow-up, consultar_cadastro, evaluation, portal FAQ) |
| `tozi/Tozi SDR - Documento Executivo.md` | Versão executiva do sistema |
| `tozi/analise-atendimentos/` | `ANALISE-COMPORTAMENTAL.md` (9 conversas reais, corretor Henrique), `PLAYBOOK-VENDAS-TOZI.md`, `FAQ-TOZI.md`, `julia-vendas-PROPOSTA.md` |
| `chatspx/TOZI-AGENT-SPEC.md` (raiz, 45 KB) | Spec de portabilidade n8n→Rails (abril/2026) — blueprint da migração |

---

## 1. Inventário de capacidades da Clara no n8n

### 1.1 Normalização e roteamento (node `Normalizar`, code node no workflow principal)

Coração do sistema: recebe o webhook bruto do SPX, classifica e roteia. Código completo extraído do JSON:

- **Classificação de autor:** `cliente` (Contact), `atendente` (User), `clara`/`bot_nota` (AgentBot público/privado), `sistema` (activity). Detecção defensiva de Contact (sem campo `type`, infere por `phone_number`/`identifier`/`message_type==incoming`).
- **Classificação de conteúdo:** `texto`, `imagem`, `audio`, `video`, `documento`, `localizacao`, `sticker`, `contato` (vCard com extração de nome+telefone do attachment), `sem_conteudo`. Gera `texto_humano` legível (`[Áudio enviado pelo cliente]` + legenda).
- **Rotas e regras (na ordem):**
  | Regra | Condição | Rota |
  |---|---|---|
  | 0 | `conversation_status_changed` → resolved | `limpar` (atendimento=false + labels do contato zeradas) |
  | 1 | activity (`message_type==2`) | `ignorar` |
  | 2 | `content_attributes.nps_survey == true` | `ignorar` |
  | 3 | sender agent_bot | `ignorar` |
  | 4 | cliente + conversa resolved + texto é número 0-10 + tem team | `ignorar` (provável resposta NPS) |
  | 5 | cliente com `custom_attributes.atendimento == true` | `ignorar` (em atendimento humano) |
  | 5b | cliente + mídia processável | `midia` → rota_final `clara` |
  | 5c | cliente + texto | `clara` |
  | 6a | atendente + nota privada com `#tozi` | `copiloto` |
  | 6b | atendente + público | `marcar` (atendimento=true + label `atendimento` no contato) |
  | 7 | fallback | `ignorar` |
- **Filtro de teste:** node `Filtro Teste (so Paulo)` — só processava `conversation.id == 2159` (whitelist de conversa, modo teste).

### 1.2 Debounce de mensagens picadas (Redis buffer)

- `Buffer Push` → lista Redis `tozi.buffer.{conversa_id}` com `texto_humano`.
- `Aguarda Debounce` (Wait **15s**) → `Buffer Get` → `Verifica Buffer`: só processa se a **última** mensagem do buffer for a desta execução (execuções anteriores morrem em silêncio) → `Buffer Clear` → `Prepara Input Clara` junta tudo com `\n`.

### 1.3 Agente Clara (pré-atendimento)

- **LLM:** node `LLM Clara` = `gpt-5.2-chat-latest` (o doc `prompt-clara.md` cita GPT-4.1-mini — o workflow está mais novo que o doc).
- **Memória:** Postgres Chat Memory, tabela `tozi_chat_historicos`, sessionKey `tozi.chat.memory.{conversa_id}`, janela de **10** mensagens.
- **Tools:** `faq_tozi` (vector store **in-memory** retrieve-as-tool + embeddings OpenAI — volátil), `Think` (raciocínio), `Atribuidor` (agentTool/subagente).
- **Prompt (9.314 chars, no node `Agente Clara`):** persona humana e concisa (1-3 frases, uma pergunta por vez, máx 1 emoji), **dois modos por horário comercial** (dentro: entender + confirmar nome + atribuir rápido; fora: qualificar fundo, dossiê rico pro time pegar de manhã), **confirmação do nome real** antes do handoff (nome do WhatsApp pode ser apelido), identificação de momento (social / interesse vago / interesse claro), coleta por tipo de demanda (comercial: tipo, finalidade, região, valor, quartos, pets, prazo; suporte: problema + endereço, rápido), guardrails (não busca imóveis pro cliente, não agenda, não negocia, não pede documento, não inventa).
- **Contexto injetado:** nome do cliente (WhatsApp), atendente atribuído ("não atribua de novo se já tem alguém"), **resumo prévio** de `custom_attributes.resumo` ("não faça o cliente repetir").
- **Data/hora dinâmica no prompt:** função Luxon embutida que calcula em runtime: agora, dentro/fora do horário, e **a próxima abertura humanizada** ("hoje às 13:30" / "amanhã às 7:30" / "Segunda às 7:30"). Tabela: Seg-Sex 7:30-11:30 e 13:30-17:30; Sáb 9:00-11:30; Dom fechado.
- **Output:** JSON `{"messages": ["..."]}` com 1-2 mensagens.

### 1.4 Subagente Atribuidor (enriquecimento + handoff)

- agentTool (`gpt-4.1-mini`, sem memória). A Clara chama em linguagem natural ("João Silva quer alugar casa em Sinop, até 2000, 3 quartos, tem cachorro").
- Lógica de decisão (system prompt no node `Atribuidor`): tem critérios → `buscar_imoveis`; referência geográfica → `buscar_localizacao` antes; suporte com nome → `consultar_cadastro` (tool **nunca implementada**); vago → só resumo.
- Saída sempre via `atribuir_atendimento`: **resumo obrigatório** (nota privada) + **sugestão opcional** (segunda nota privada com imóveis e links do site).
- O subworkflow `Tozi TOOL - Atribuir Atendimento` (ID PTHEJTw8ZWkgXt7F, 8 nodes, documentado em `tozi/README.md:204-222`): atribui `assignee_id: 66` (**Camila, pessoa fixa** — sem round-robin nem time), envia as notas, **reabre a conversa (`status: open`)**, retorna "atribuído.".
- Inputs fixos injetados do Normalizar: `sender_id` (contato) e `chat_id` (conversa).

### 1.5 Humanizador (formatação WhatsApp)

- `Basic LLM Chain` (`gpt-4.1-mini`) + Structured Output Parser (`gpt-4.1-mini`): quebra a resposta da Clara em **1-2 mensagens, máx 3 frases cada**, sem mudar conteúdo, emoji só se já tinha. Schema JSON `messages` (minItems 1, maxItems 2). Depois `Separa Mensagens` → `Loop Enviar` → POST `/api/v1/accounts/6/conversations/{id}/messages`.

### 1.6 Copiloto (assistente interno `#tozi`)

- Trigger: nota **privada** de atendente contendo `#tozi` (case-insensitive; o Normalizar remove a hashtag).
- `GET Historico` (API messages) → `Formatar Historico` (code): filtra activity/vazias, **últimas 30 mensagens**, cap de **6.000 chars**, formato `[Cliente]/[Clara]/[Atendente]/[Interno] (privado): texto`, e monta `prompt_copiloto` = histórico + "Pergunta de {atendente}: {texto}".
- Agente (`gpt-5.2-chat-latest`) com tools próprias: `buscar_imoveis`, `buscar_localizacao`, `faq_tozi`, `Think` (e `consultar_conversa`/`consultar_cadastro` descritas no prompt, a segunda nunca implementada).
- Comportamento: direto, não faz perguntas ao atendente. Resposta enviada como **nota privada** (`Envia Resposta Copiloto`, `private: true`).

### 1.7 Pipeline de mídia (transcrição + visão)

- Rota `midia` → `Tipo Mídia` (switch): áudio → `Download Audio` + `Whisper Transcricao`; imagem → `Vision Analise Imagem` (`gpt-4o-mini`, prompt imobiliário específico: tipo de imagem, características do imóvel, **placa aluga-se/vende-se + código numérico**, OCR de texto/valores/telefones, descrição p/ atendente); outros tipos → fallback com `texto_humano`.
- `Formatar Mídia` → **nota privada** no chat: `📎 Transcrição de áudio do cliente (12s): ...` / `📎 Descrição de imagem do cliente: ... Legenda: ...` — visível pro time humano.
- `Rota Final`: se autor era cliente → segue pra Clara com `texto_final` no lugar da mensagem; se era **atendente** → `marcar` atendimento (mídia de atendente também era transcrita/analisada, só pra registro).

### 1.8 Trava de atendimento humano (estado `atendimento`)

- `Set Atendimento True` + `Adiciona Label (pos-marcar)`: quando atendente responde público, seta `custom_attributes.atendimento=true` na conversa e label `atendimento` no **contato**.
- `Set Atendimento False` + `Remove Label (pos-limpar)`: quando a conversa é resolvida, zera o atributo e **apaga todas as labels do contato** (`labels: []` — efeito colateral bruto).
- Cliente com `atendimento=true` → Clara fica calada (regra 5 do Normalizar).

### 1.9 Tools (subworkflows)

- **`buscar_imoveis`** (`subworkflows/Tozi TOOL - Buscar imóveis.json`): GET `https://toz19328-rest.vistahost.com.br/imoveis/listar` com `pesquisa={fields(18), filter, advFilter, order, paginacao}` + `showtotal=1`; gera URL do site `https://www.toziimoveis.com.br/{slug(TituloSite)}-{slug(Cidade)},{ImoCodigo||Codigo}`. A descrição da tool (no node `buscar_imoveis` do workflow principal) ensina a gramática Vista: `Status: ["like","%alug%"]` p/ locação, `ValorLocacao: ["",2000]`, advFilter com `Or` aninhado, `CaracteristicaComplementar like %piscina%`, estratégia progressiva (começa amplo, refina), paginação 5.
- **`buscar_localizacao`** (ID dTUGxaH5AwEDFen0, não está em disco; doc em `README.md:192-202` + `tools-descricoes.md:81-113`): geocoding ("sempre complete com 'sinop mt'") → **bounding box de 3 km** em `Latitude`/`Longitude` pro filtro Vista.
- **`atribuir_atendimento`** — ver §1.4.
- **`consultar_cadastro`** — *"pendente implementação. Endpoint Vista ainda não definido"* (`tools-descricoes.md:168-176`).

### 1.10 O que o n8n **NÃO** tinha (mitos a desfazer)

- **Follow-up com timing NÃO existia** — era o item 2.1 do `tozi/BACKLOG.md` (🔴 não iniciado): critérios propostos = ocioso 3+ dias, máx 2 follow-ups, intervalo mínimo 2 dias, **não enviar fora do horário comercial**, mensagens por cenário (locação/suporte/genérico). O SPX implementou isso (melhor) do zero.
- Sem envio de fotos de imóvel ao cliente.
- Sem state machine de funil/kanban.
- Sem HSM/templates (canal WAHA = texto livre, sem janela de 24h).
- Sem dedup de resposta, sem "[IGNORAR]", sem typing indicator.
- `consultar_cadastro` e "perguntar ao grupo de gerentes" nunca saíram do papel.
- Evaluation de conversas (IA↔cliente e atendente↔cliente) e Portal de FAQ p/ gerentes: backlog puro (`BACKLOG.md:119-241`).

### 1.11 Modelos usados no n8n

| Papel | Modelo |
|---|---|
| Clara | gpt-5.2-chat-latest |
| Copiloto | gpt-5.2-chat-latest |
| Atribuidor | gpt-4.1-mini |
| Humanizador + Parser | gpt-4.1-mini |
| Vision | gpt-4o-mini |
| Transcrição | Whisper |

---

## 2. O que JÁ migrou pro Captain v2 (com referência no chatspx)

| Capacidade n8n | Equivalente SPX | Observações |
|---|---|---|
| Normalizar/roteamento | `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-44` (`trigger_templates` → `process_captain_behavior`) + `enterprise/app/services/captain/behavior/router_service.rb` | Entry point único de toda mensagem. Router cobre: activity skip, vazio skip (linhas 10-11), whitelist `only_contact_phones` **com variações do 9º dígito BR** (router_service.rb:47-63 — o mesmo bug que o disparo teve, aqui já tratado), `skip_labels`, `skip_groups` (detecta `@g.us` em 3 campos, linhas 82-95), `skip_agent_bot`, `skip_after_human_response` (linhas 105-117). |
| Trava `atendimento` | `custom_attributes.atendimento_humano` (checkbox painel) — `hook_execution_service.rb:137-140` + `followup_job.rb:17`; e `skip_after_human_response` dinâmico no router | Semântica mudou: no n8n era automática (atendente falou → trava; resolved → destrava). No SPX a trava manual + skip dinâmico cobrem o caso, mas **não há "destravar no resolved" nem label visível no contato** (ver gaps). |
| Debounce 15s Redis | `enterprise/app/services/captain/behavior/debounce_service.rb` (token + TTL buffer 30s) → `Captain::Conversation::DebouncedResponseJob` | Mesmo conceito, implementação mais robusta (token UUID em vez de comparar último texto). `debounce_seconds` configurável no behavior JSONB. |
| Humanizador (LLM) | `enterprise/app/services/captain/behavior/humanizer_service.rb` — **determinístico** (split por parágrafo + frase, `max_chars` 300) | Sem custo/latência de LLM. Plus: typing indicator em rajada + delay proporcional por chunk (`response_builder_job.rb:205-241`) e sanitização de markdown p/ WhatsApp (`response_builder_job.rb:191-203`). |
| Copiloto `#tozi` | `enterprise/app/services/captain/behavior/copilot_trigger_service.rb` (hashtag configurável, default `#copilot`) → `Captain::Copilot::ChatService` + 31 copilot services em `enterprise/app/services/captain/tools/copilot/` | Vai muito além do n8n (workload de agentes, stats, transferência de inbox, send_template etc.). Ver gap 5: confirmar acesso do copiloto às tools Tozi (buscar_imovel). |
| Transcrição de áudio | `enterprise/app/services/captain/behavior/media_pipeline_service.rb` + `Messages::AudioTranscriptionService` (`enterprise/app/services/messages/audio_transcription_service.rb`); transcrição entra no contexto via `Captain::OpenAiMessageBuilderService#extract_audio_transcriptions` | Commit recente `1671b9017` garantiu transcrição também com `captain_integration_v2`. |
| Análise de imagem | **Parcial, por outro caminho:** `Captain::OpenAiMessageBuilderService#attachment_parts` injeta imagens como `image_url` multimodal direto pro agente (open_ai_message_builder_service.rb:34-51) | O agente "vê" a imagem nativamente (melhor que descrição intermediária), MAS perdeu-se a **nota privada 📎 pro atendente** e o prompt imobiliário específico (placa/código). `media_pipeline_service.rb:17` menciona flag `image_description` que **não tem implementação** (process só transcreve áudio). |
| buscar_imoveis | `enterprise/lib/captain/tools/buscar_imovel_tool.rb` (built-in, params estruturados: status_tipo/categoria/bairro/endereco/valor_max/dormitorios/bbox) | Mais robusto que a query JSON crua do n8n (LLM não monta mais `["like","%alug%"]` na mão). URL corrigida com `ImoCodigo` (linhas 79-88). Filtro de bairro virou like parcial. Perdeu-se: advFilter/Or de múltiplos bairros, `CaracteristicaComplementar` (piscina etc.), ordenação por valor. |
| buscar_localizacao | Custom tool #4 "Buscar localização (geocoding)" — registro `Captain::CustomTool` (`enterprise/app/models/captain/custom_tool.rb`) com a chave Google embutida na endpoint_url (dado em prod, não código) | Mesmo contrato (bbox ~3km alimenta o buscar_imovel). |
| atribuir_atendimento | `enterprise/lib/captain/tools/handoff_tool.rb`: nota privada com o motivo/dossiê (linhas 26-37) + `bot_handoff!` + **round-robin de agente online** via `AutoAssignment::AgentAssignmentService` (linhas 52-63) | n8n atribuía à Camila fixa; SPX faz round-robin de qualquer membro do inbox. **Roleta por nicho é TODO explícito** (handoff_tool.rb:43-45 e 74-84). |
| faq_tozi (vector volátil) | Knowledge nativa pgvector: `Captain::AssistantResponse` (40 Q&A) + `Captain::Document`/chunks (Playbook, 19 chunks), modo `hybrid`; `enterprise/lib/captain/tools/faq_lookup_tool.rb` | Persistente, editável pela UI (CRUD de Q&A deployado). |
| Horário comercial | `enterprise/app/services/captain/behavior/business_hours_checker.rb` + `outside_hours_action=='ignore'` (hook_execution_service.rb:50-53) | Só decide skip. O "modo fora do horário" (qualificar mais) vive no prompt da Júlia. **Não há injeção dinâmica de "próxima abertura"** no prompt (gap 8). |
| Memória Postgres (janela 10) | Histórico real da conversa do banco (`response_builder_job.rb:64-83`) com reply-context de citações WhatsApp (linhas 103-118) | Superior. Conversation custom_attributes e contact entram no **state** do agente (`enterprise/app/services/captain/assistant/agent_runner_service.rb:10-16,158-160`). |
| Output {messages:[]} máx 2 | Humanizer split sem máximo de 2 (picado por parágrafo) | Comportamento diferente, intencional. |

### Capacidades NOVAS no SPX sem equivalente n8n (implementam o backlog do n8n)

- **Follow-up in-window decidido pelo agente:** `enterprise/lib/captain/tools/programar_followup_tool.rb` (2 min–2 dias, token substituível) + `enterprise/app/jobs/captain/conversation/followup_job.rb` (MAX_FOLLOWUPS=4, quiet hours 21h–8h America/Cuiaba com remarcação pra manhã, cancela se cliente respondeu/trava humana/resolvida; esgotou → lead `esfriado` + funil "Frio" + cadência HSM). Reset da cadência quando o lead responde (`response_builder_job.rb:87-94`).
- **Cadência HSM fora da janela 24h:** `app/services/spx/tozi/reactivation_cadence_service.rb` (1d/3d/7d, só Cloud API, cancel-on-reply).
- **Funil/kanban com state machine:** `app/listeners/spx/tozi/funnel_automation_listener.rb` (incoming em estágio de espera → "Em Conversa"; handoff a humano → "Qualificado") + `app/services/spx/tozi/funnel_placement_service.rb`.
- **Perfil do lead:** `enterprise/lib/captain/tools/salvar_info_lead_tool.rb` (`tozi_status_lead`, `sobre_cliente`, label `followup-ativo`, espelha no funil).
- **Fotos de imóvel ao cliente:** `enterprise/lib/captain/tools/enviar_fotos_imovel_tool.rb` (lotes de 3, offset por conversa, intervalo 2s).
- **Dedup de resposta** (`dedup_service.rb`), **[IGNORAR]** (response_builder_job.rb:163-167), **typing/read receipt** (hook_execution_service.rb:86-93), **auto-open quando a IA assume** (hook_execution_service.rb:59-71, commit `f96ae7740` — ataca o limbo pending).

---

## 3. Gaps funcionais — o que AINDA NÃO migrou

1. **Dossiê enriquecido no handoff (o "Atribuidor")** — no n8n o corretor recebia **duas notas privadas**: resumo estruturado + **sugestão de imóveis com links** buscados automaticamente na hora do handoff. No SPX, o `HandoffTool` só posta o `reason` que o agente escrever (handoff_tool.rb:26-37); não há subagente que enriqueça com busca Vista antes de entregar. O prompt da Júlia pede "dossiê no motivo" (julia-vendas-PROPOSTA.md §handoff), mas é best-effort do LLM.
2. **Atribuição por nicho/time** — n8n: Camila fixa (id 66). Spec Júlia: roleta por nicho + Mayara (problemas/falar com humano), Letícia (suporte/boleto/contrato), Bruna (locação). SPX hoje: round-robin de **qualquer** agente online do inbox (handoff_tool.rb:52-63), com TODO explícito de team_id/priority/escalation (linhas 74-84). Os times do TOZI-AGENT-SPEC.md:1437-1440 (TIME_LOCACAO_ID=50, TIME_VENDAS_ID=49, TIME_FINANCEIRO=56, TIME_MANUTENCAO=53) nunca foram usados. **É exatamente aqui que a IA orquestradora precisa plugar.**
3. **Nota privada de mídia pro time humano** — n8n postava `📎 Transcrição/Descrição` como nota privada visível pros atendentes (inclusive de mídia enviada **pelo atendente**). No SPX a transcrição/imagem vai só pro contexto do LLM; o humano que abrir a conversa não vê transcrição de áudio. `image_description` está prevista no behavior (`media_pipeline_service.rb:17`) mas sem implementação; e o prompt imobiliário de visão (placa aluga-se/vende-se + código — `prompt-vision-imagem.md`) se perdeu.
4. **`consultar_cadastro` (Vista — inquilinos/proprietários)** — nunca existiu em lugar nenhum (n8n BACKLOG.md item 1.1; nenhuma tool no chatspx — `rg consultar_cadastro` vazio). Bloqueia o fluxo de **suporte** (boleto/contrato/manutenção), que era um dos 3 tipos de atendimento da Clara.
5. **Copiloto com tools Tozi** — o trigger existe (`copilot_trigger_service.rb`), mas o copiloto n8n buscava imóveis/localização/FAQ pro atendente. Conferir se o `Captain::Copilot::ChatService` expõe as public tools do assistant (buscar_imovel etc.) ou só as copilot tools genéricas; o comportamento "responde como nota privada na própria conversa" também precisa de validação E2E.
6. **Marcar/limpar atendimento automático e visível** — n8n: atendente respondeu → label `atendimento` no contato; resolved → limpa. SPX cobre funcionalmente via `skip_after_human_response` (dinâmico) + checkbox `atendimento_humano` (manual), mas: (a) não há reset automático da trava manual no resolved; (b) não há sinal visível (label) de "humano assumiu" pra relatórios/filas. Obs.: o n8n tinha o bug de zerar **todas** as labels do contato no limpar — não copiar isso.
7. **Resumo prévio no prompt** — Clara n8n recebia `custom_attributes.resumo` pra não fazer o cliente repetir. No SPX, `custom_attributes` da conversa e do contato entram no **state** do runner (agent_runner_service.rb:10-16,158-160), mas não está claro que o LLM os veja no prompt — `sobre_cliente`/`tozi_status_lead` salvos pelo SalvarInfoLeadTool precisam comprovadamente voltar ao contexto na conversa seguinte (continuidade entre sessões/handoffs).
8. **"O time retorna amanhã às 7:30"** — o n8n calculava a próxima abertura em runtime e injetava no prompt (função Luxon no system message do `Agente Clara`). O `BusinessHoursChecker` do SPX só decide skip/responder; não injeta data/hora atual nem próxima abertura — a IA pode alucinar horário se o cliente perguntar.
9. **Busca avançada Vista** — advFilter (múltiplos bairros via Or), `CaracteristicaComplementar` (piscina, mobiliado...), ordenação por valor e paginação além de 5 não existem no `BuscarImovelTool` (params fixos). Eram usados pelo Copiloto/Atribuidor n8n.
10. **Backlog herdado intacto:** evaluation IA↔cliente e atendente↔cliente (LLM-as-judge), portal de FAQ/playbooks pra gerentes, tool "perguntar ao grupo de gerentes" com captura da resposta pra FAQ (loop de melhoria), Copiloto v2 observador (BACKLOG.md §§2-5) — relevantes pro objetivo de IA orquestradora.

---

## 4. Regras de negócio embutidas nos fluxos (precisam sobreviver no SPX)

### Horários e tempos
- **Horário comercial Tozi:** Seg-Sex 7:30-11:30 e 13:30-17:30; Sáb 9:00-11:30; Dom fechado. TZ **America/Cuiaba** (workflow `Agente Clara` system message; TOZI-AGENT-SPEC.md:851-869).
- **Dois modos por horário:** dentro = entender + confirmar nome + atribuir RÁPIDO (o time aprofunda); fora = qualificar fundo, uma pergunta por vez, e avisar **a data/hora específica da próxima abertura**.
- **Debounce:** 15s (n8n e behavior atual).
- **Follow-up (do backlog n8n + observação do Henrique):** régua D+1/D+3/D+7 sugerida (`ANALISE-COMPORTAMENTAL.md` D4); máx 2-3 tentativas (BACKLOG.md:113-115 — SPX usa 4); intervalo mínimo 2 dias entre follow-ups; **nunca fora do horário comercial** (SPX relaxa pra quiet hours 21h-8h); follow-up matinal 7h-9h era o timing do corretor de alta conversão (C5).

### Qualificação e triagem
- **Confirmação do nome real** antes de qualquer handoff (nome do WhatsApp pode ser apelido/empresa). Não re-perguntar se já se apresentou.
- **Não atribuir se já há assignee** ("Atribuído à" no contexto).
- **Coleta comercial:** o que procura, finalidade, região/bairro, faixa de valor, quartos, pets, prazo. **Suporte:** problema + endereço, coleta rápida e atribui independente do horário.
- **Qualificação humanizada (direção do Guilherme, gerente):** *"não quero SDR que pergunta 'qual sua renda bruta'"* — descobrir a PESSOA antes dos números (julia-vendas-PROPOSTA.md §2). As 4 perguntas do Henrique (renda bruta, nascimento, filhos, 3+ anos de carteira — ANALISE-COMPORTAMENTAL.md C1) são conhecimento do corretor, não script da IA.
- **5 nichos** com discurso próprio: MCMV/Pacaembu, aptos SPL na planta, terrenos/loteamentos, casas prontas/usadas, na planta (PLAYBOOK §2). **Triagem de interesse real** (clicou num nicho mas quer outro).
- **Roteamento de não-venda:** problemas/tirar imóvel/falar com humano → Mayara; suporte/boleto/contrato → Letícia; locação → Bruna (julia-vendas-PROPOSTA.md §handoff).
- **Represamento de lançamentos:** capturar interesse, alinhar expectativa honesta, follow-up até lançar.

### Handoff
- **Resumo sempre obrigatório**; sugestão de imóveis só com resultados concretos; sempre a última ação; avisar o cliente com naturalidade (dentro do horário: "vou passar pro time"; fora: "retornam no próximo expediente" com dia/hora).

### Busca de imóveis (gramática Vista)
- `Cidade=Sinop` default; `Status like %alug%`/`%vend%` SEMPRE; valores como ranges `["",max]`; bairro direto ou bbox 3 km do geocoding ("sempre completar com 'sinop mt'"); paginação 5; nunca lista grande pro cliente (1-2 opções); usar valores/links exatamente como retornados.

### Ignorar/ruído
- Grupos (`@g.us`), activity, NPS (flag `nps_survey` E heurística número 0-10 em conversa resolvida com team), mensagens do próprio bot, conteúdo vazio.

### Guardrails (todos os agentes)
- **NUNCA pedir senha/credencial** (gov.br, banco) — anti-padrão D1 observado no corretor humano (ANALISE-COMPORTAMENTAL.md:164).
- Não simular financiamento nem prometer subsídio/parcela (corretor faz); calibrar expectativa simulação≠aprovação (D2).
- Não passar endereço completo em vendas (só bairro/região); não negociar/dar desconto; não pedir CPF/RG/comprovante; não inventar imóvel/preço/condição.
- Toda informação crítica **em texto** (mesmo se também em áudio) — D5.
- Urgência só quando real e específica (desconto que acaba, unidade que some) — A3.
- Tom "de Sinop": caloroso, espelha humor, léxico do Playbook §7 (banco de falas é referência de intenção, não script).

### Pontos de cuidado herdados
- O `limpar` do n8n zerava TODAS as labels do contato — comportamento destrutivo a não replicar.
- A reabertura da conversa no handoff (n8n setava `open`) é o que mantém a conversa visível — o SPX faz via `bot_handoff!` + `ensure_conversation_open`; coerente com o incidente do limbo pending.

---

## 5. Hooks pra IA orquestradora (síntese)

1. `Enterprise::MessageTemplates::HookExecutionService#trigger_templates` (enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4) — funil único de toda mensagem incoming; é o "Normalizar" do SPX e o lugar de plugar triagem.
2. `Captain::Behavior::RouterService` + behavior JSONB do assistant — política declarativa de "a IA atende ou não" (whitelist, labels, grupos, pós-humano).
3. `Captain::Tools::HandoffTool#assign_to_available_agent` (handoff_tool.rb:52) — ponto exato pra roleta por nicho/time/corretor (TODO já anotado pelo próprio código).
4. `Spx::Tozi::FunnelAutomationListener` (app/listeners/spx/tozi/funnel_automation_listener.rb) via AsyncDispatcher — eventos `message_created`/`assignee_changed` movendo kanban; extensível pra outros eventos.
5. `Captain::Tools::ProgramarFollowupTool` + `Captain::Conversation::FollowupJob` — follow-up agentico in-window; `Spx::Tozi::ReactivationCadenceService` — HSM fora da janela.
6. `Captain::CustomTool` (enterprise/app/models/captain/custom_tool.rb) — integração HTTP declarativa com CRM externo (caminho natural pro `consultar_cadastro` Vista sem código).
7. `Captain::AssistantLog` — telemetria de decisões (router_skip, business_hours_skip, copilot_trigger, dedup_skip, humanizer_split) pra observabilidade da orquestração.
8. `Captain::Behavior::CopilotTriggerService` — copiloto interno por hashtag em nota privada (com gap de tools Tozi a fechar).
