# Roadmap — IA completa no SPX ("faz o que um humano faria")

> **Data:** 2026-06-10 · **Visão do Paulo:** uma IA que atende como um humano completo — entende qualquer coisa que o cliente mande, age dentro da ferramenta, lembra, antecipa e melhora sozinha. Construída por partes.
> **Base:** `docs/MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md` (o que existe) + `docs/PLANO-GOLIVE-IA-2026-06-11.md` (Onda 0).
> Cada item marca a **alavanca** (o que o fork já tem pronto pra apoiar) e o **esforço** (P = horas, M = dias, G = semana+).

```
O0 GO-LIVE      O1 PERCEPÇÃO     O2 MÃOS         O3 MEMÓRIA      O4 PROATIVIDADE   O5 NEGÓCIO       O6 AUTOCRÍTICA   O7 PRODUTO
(11-12/06)      (sentidos)       (age no SPX)    (lembra)        (antecipa)        (Vista fundo)    (evals/copilot)  (multi-cliente)
texto·áudio  →  PDF·doc·vídeo →  atribui·funil → perfil do    →  vigia·retoma  →   boleto·contrato→ IA que audita →  N clientes
imagem·sticker  localização      etiqueta·agenda  lead no prompt  agenda visita     2ª via·cadastro  IA e humanos
```

---

## Onda 0 — Go-live (11–12/06) ✅ planejada

Texto + **áudio** (patch T1) + **imagem/figurinha** (visão nativa, já funciona) + busca Vista + fotos + follow-up + handoff com notificação. Plano executável próprio.

**Pronto quando:** 13/13 do roteiro E2E passam e leads reais são atendidos sem intervenção.

---

## Onda 1 — Percepção completa (a IA entende TUDO que chega) · ~1 semana

O cliente manda qualquer coisa e a Clara entende — e o humano que abrir a conversa também vê o que a IA entendeu.

| Entrega | Como | Alavanca existente | Esforço |
|---|---|---|---|
| **1.1 PDF e documentos** (contrato, boleto, matrícula, proposta) | Extrair texto server-side (`pdftotext`/poppler); PDF escaneado → renderizar páginas como imagem e mandar pra visão do modelo (sem OCR clássico). Resumo entra no contexto da conversa; arquivo grande → sumarização LLM + texto íntegro em nota | `OpenAiMessageBuilderService#attachment_parts` (ponto único de extensão — hoje trata image/audio, ignora `file`); o transporte de anexo já existe | **M** |
| **1.2 Nota privada 📎 de mídia** (paridade n8n) | Transcrição de áudio + descrição de imagem + resumo de documento postados como **nota privada** visível pro corretor (hoje só o LLM "vê") | n8n fazia ("📎 Transcrição de áudio (12s): …"); `AddPrivateNoteTool`/`Messages::MessageBuilder` com `private: true`; flag `media_pipeline.image_description` já existe no behavior (sem implementação — implementar aqui) | **P** |
| **1.3 Visão imobiliária dirigida** | Prompt de visão específico: placa "aluga-se/vende-se" + código do imóvel na placa → dispara `buscar_imovel` pelo código; print de anúncio → extrai referência | Prompt já escrito no n8n (`tozi/prompts/prompt-vision-imagem.md`); visão nativa já ativa | **P** |
| **1.4 Localização compartilhada** | Cliente manda pin do WhatsApp → lat/lng → `buscar_imovel` por raio (bbox já suportado) | `attach_location` no incoming já grava coordenadas; tool já aceita lat/lng | **P** |
| **1.5 Vídeo** | Extrair trilha de áudio → Whisper (mesmo pipeline do áudio); frames só se houver demanda real | `AudioTranscriptionService` + ffmpeg | **M** (adiar se sem demanda) |
| **1.6 RAG por arquivo** (o caso n8n: "responda sobre ESTE arquivo") | Documento grande da conversa → chunk + embedding ad-hoc vinculado à conversa, consultável pela tool de knowledge | `Captain::Document`/`DocumentChunk` + pgvector + `hybrid_search` JÁ EXISTEM (usados no Playbook) — é reaproveitar o mesmo encanamento com escopo "conversa" em vez de "assistant" | **M** |

**Pronto quando:** cliente manda contrato em PDF e pergunta "posso rescindir antes?" → Clara responde citando a cláusula, e o corretor vê o resumo em nota privada.

---

## Onda 2 — Mãos completas (a IA opera o SPX como um atendente) · ~1–2 semanas

É a Fase 1 do plano-mestre de orquestração, vista pela ótica de capacidade.

| Entrega | Alavanca | Esforço |
|---|---|---|
| **2.1 Atribuir direcionado** — tool `atribuir(corretor/time/nicho)` no agente (hoje só round-robin cego do handoff) | TODO já anotado em `handoff_tool.rb:74-84`; lógica pronta no copilot `AssignConversationService` — portar pro padrão `BasePublicTool` (~20 linhas, padrão provado 4×) | **P** |
| **2.2 Triagem por nicho** — Clara etiqueta `nicho:*` → automation rule `assign_team` + SLA | Ciclo label→`CONVERSATION_UPDATED`→automation **já funciona fim-a-fim** (spec do fork prova); falta só provisionar labels + regras | **P** |
| **2.3 Mover funil explícito** — tool `mover_card(estagio)` (hoje só efeito colateral) | `FunnelPlacementService.move/current_type` já é a API; embrulhar em tool é trivial | **P** |
| **2.4 Agendar HSM** — a IA agenda template fora da janela em qualquer conversa | `ScheduledMessages` + `template_params` prontos; expor na API/tool | **P** |
| **2.5 Cross-conversation** — agir em OUTRA conversa (ex.: avisar o corretor noutro fio) | Copilot tools já fazem (`send_message(conversation_id)`); agent tools são presas ao state — criar variantes com guardrails | **M** |
| **2.6 Aposentar a regra #53** — triagem com dono certo substitui o "zerar tudo" | Mapeado: #53 e IA são mutuamente exclusivas | **P** (decisão + regra nova) |
| **2.7 Criar contato/conversa outbound** (a IA inicia contato sob instrução) | `DisparoLeadJob` é o template (ficha reconciliada + conversa única + HSM) — generalizar em service | **M** |

**Pronto quando:** lead orgânico entra → Clara qualifica → etiqueta o nicho → atribui ao time/corretor certo → notificação chega → card no estágio certo — sem humano no meio.

---

## Onda 3 — Memória (a IA lembra como um humano que conhece o cliente) · ~1 semana

| Entrega | Alavanca | Esforço |
|---|---|---|
| **3.1 Perfil estruturado do lead que VOLTA ao prompt** — renda aproximada, bairros de interesse, pets, prazo, nicho | `ContactAttributesService` está **80% pronto e órfão** (prompt incluso, update stubado); `contact.custom_attributes` já entram no prompt via `feature_contact_attributes` (true por backfill) | **M** |
| **3.2 Resumo vivo da conversa** — custom attribute `resumo` atualizado a cada N turnos (o corretor pega o fio em 10s; a Clara não faz o cliente repetir) | Custom attribute `resumo` JÁ EXISTE em prod (legado n8n); `salvar_info_lead` é o padrão de escrita | **P** |
| **3.3 Dossiê de handoff enriquecido** (paridade n8n "Atribuidor") — nota privada com resumo + sugestões de imóveis buscadas na hora | n8n mandava 2 notas; `HandoffTool` posta só o motivo — enriquecer com chamada ao `buscar_imovel` antes de entregar | **M** |
| **3.4 Política de memória entre episódios** — conversa única já é a memória longa; definir poda/compactação de threads gigantes (prompt cresce sem limite hoje — `MAX_MESSAGE_LENGTH` é constante morta) | Histórico integral já vai ao modelo; implementar janela + resumo acumulado (3.2 alimenta) | **M** |

**Pronto quando:** cliente que conversou há 3 semanas volta e a Clara retoma do ponto certo ("da última vez você procurava 3 quartos perto da UNEMAT — ainda vale?").

---

## Onda 4 — Proatividade (a IA não espera) · ~1–2 semanas

| Entrega | Alavanca | Esforço |
|---|---|---|
| **4.1 Vigia de leads esperando** — SLA nrt-only por automação + escalação (era a falha das 432) | Módulo SLA **funciona e está no cron** (descoberta do mapeamento); receita anti-ruído documentada | **P** |
| **4.2 Retomada dirigida** — orquestrador acorda a Clara em conversas paradas com instrução ("lead sumiu pós-proposta, retome") | `ResponseBuilderJob(directive:)` é genérico — é como o follow-up já funciona | **P** |
| **4.3 Agendamento de visita** — tool `agendar_visita` → card "Agendado" (único estágio sem trigger) + Google Calendar do corretor + lembrete HSM `tozi_followup_horario_combinado` (template já aprovado) | Estágio `agendado` existe; template existe; Calendar = custom tool HTTP | **M** |
| **4.4 Reativação de frios com inteligência** — em vez de cadência fixa 1d/3d/7d, a IA escolhe template/momento pelo perfil (3.1) e performance (taxa de resposta por template já é consultável) | `ReactivationCadenceService` + `campaign_stats`; generalizar config p/ `behavior` JSONB | **M** |
| **4.5 Pós-venda/pesquisa** — X dias após resolução, mensagem de satisfação/indicação | `ScheduledMessages` + CSAT nativo | **P** |

**Pronto quando:** nenhum lead fica >2h esperando sem alguém (humano ou IA) ser cobrado, e visita marcada vira evento + lembrete sem toque humano.

---

## Onda 5 — Negócio fundo (a IA resolve como a Letícia do financeiro) · ~2 semanas

O que faltava no n8n e continua faltando: o fluxo de SUPORTE (1 dos 3 tipos de atendimento).

| Entrega | Alavanca | Esforço |
|---|---|---|
| **5.1 `consultar_cadastro` no Vista** — inquilino/proprietário: contrato, vencimentos, status | Nunca implementado (backlog n8n §1.1); `BuscarImovelTool` é o molde de tool Vista; endpoint Vista a confirmar | **M/G** |
| **5.2 2ª via de boleto** — caso nº1 do financeiro | Depende do 5.1 + endpoint Vista/banco | **M** |
| **5.3 Abertura de chamado de manutenção** — coleta problema+endereço → cria card no funil "manutenção de imóvel locado" + atribui time | Funil e time JÁ EXISTEM em prod; tool de funil (2.3) + atribuição (2.1) | **P** (após Onda 2) |
| **5.4 Status de proposta/reserva** — represamento de lançamentos com fila real | Custom attributes + funil | **M** |
| **5.5 Espelho no CRM externo** — webhooks de conta → Vista (funil/estágio/perfil sincronizados) | Webhook outbound existe; consertar retry at-most-once (fix de 1 linha mapeado) + idempotência | **M** |

**Pronto quando:** "meu boleto não chegou" é resolvido fim-a-fim pela IA, com fallback humano só em exceção.

---

## Onda 6 — Autocrítica (a IA que vigia a IA — e os humanos) · ~2 semanas

A sua visão de Evals + o Copilot completo.

| Entrega | Alavanca | Esforço |
|---|---|---|
| **6.1 Worker de Evals (porta 8910)** — LLM-judge batch de hora em hora: qualificação correta? alucinou? tool na hora certa? handoff no timing? humano deixou lead esperando? Grava veredito + alimenta a copilot tool | `get_conversation_analysis` JÁ ESPERA esse serviço (contrato/token/gate prontos); `AssistantLog` é o flight-recorder; `ConversationCompletionService` é precedente de judge | **G** |
| **6.2 Alertas acionáveis** — eval ruim → nota privada + menção ao gestor + label `eval:atencao` | Menção força push (flags T5); labels prontas | **P** (após 6.1) |
| **6.3 Copilot pleno** — `#copilot` em nota privada funcionando (passar user + postar resposta), `send_template` corrigido, tools Tozi no copilot ("busca apto 2 quartos pra esse cliente") | Painel + 32 tools prontos; 3 fixes pequenos mapeados | **M** |
| **6.4 Loop de conhecimento** — pergunta sem resposta → IA pergunta ao gestor (grupo/menção) → resposta aprovada vira Q&A na knowledge | Backlog n8n; CRUD de Q&A + embeddings prontos | **M** |
| **6.5 Painel de performance da IA** — taxa de resolução sem humano, tempo até handoff, conversão por cenário | `reporting_events` (`conversation_bot_handoff` já medido) + `AssistantLog` | **M** |

**Pronto quando:** toda manhã existe um relatório do que a IA (e o time) fez de errado ontem — e as correções de prompt/knowledge saem dele.

> **6.6 — Meta-agente (evolução da onda):** o "engenheiro residente" com harness Claude (Agent SDK) que fecha o loop sozinho — avalia, propõe E aplica melhorias via API code-first, com replay/golden-set antes de publicar e aprovação humana gradual. Tese completa, diagnóstico e quick wins (Langfuse já instrumentado, playground, golden set): **[`TESE-META-AGENTE-3-CAMADAS.md`](TESE-META-AGENTE-3-CAMADAS.md)**.

---

## Onda 7 — Produto (multi-cliente, plug-and-play) · contínuo

> **Tese de replicabilidade (10/06):** o case Tozi já está perto de replicável porque o Chatwoot é multi-tenant nativo e quase tudo que define a Clara vive em DADOS por conta (prompt, cenários, knowledge, behavior JSONB, custom tools — via API). O que prende à Tozi é uma camada fina de hardcode, finita e mapeada.

**Modelo: MOTOR (código, 1 vez) + VERTICAL PACK (dados, por nicho) + CONECTORES (aquisição).**

| Camada | Conteúdo | Estado |
|---|---|---|
| **Motor** | disparo genérico (sem `INBOX_ID=91`/brokers), cadência configurável (steps no JSONB), follow-up parametrizado (quiet hours/TZ/MAX por conta), funil engine ✅, listener gateado por conta, `LeadIntakeService` unificado, meta-agente por conta | extração = dias, não meses; destino da config já existe (`behavior` JSONB + config por inbox) |
| **Vertical Pack** (o que o onboarding instala) | funil + estágios, prompt-template (Júlia genérica com placeholders), knowledge skeleton (FAQ/playbook a preencher), templates HSM padrão (criados na WABA do cliente via `TemplateManagementService`), labels de nicho, automation rules, custom role Corretor, times, tools de negócio | material Tozi = template do nicho imobiliário |
| **Conectores** | Meta Lead Ads ✅ (multi-conta por page_id — é o MOLDE; consertar source_id + 1ª msg HSM primeiro), Google Lead Forms (mesmo padrão webhook), site/widget (nativo), CSV/disparo | todos convergem no `LeadIntakeService` |

**As 3 jogadas do plug-and-play:**
1. **`LeadIntakeService` único** — telefone reconciliado → conversa única → card no funil → 1ª mensagem conforme janela. Um caminho só = conserta uma vez, vale pra Meta/Google/site/CSV (hoje cada caminho reimplementa e é onde os bugs nascem).
2. **CRM como adapter** — `buscar_imovel` vira "tool de inventário"; cliente com CRM diferente = **custom tool HTTP sem deploy** (headers `X-Chatwoot-*` já mandam o contexto). É o que permite "imobiliárias ou não": o motor não sabe o que é imóvel; quem sabe é o pack.
3. **Onboarding como runbook executado pelo Claude Code** (code-first) — "instala o pack imobiliária na account X": criar inbox, setup_funnel, templates na WABA, assistant do template, custom tools, hooks. Meta: cliente novo em 1 dia. UI de setup só depois, se o volume justificar.

**Sequência:** (1) reconciliação rollout↔paulao [pré-requisito transversal — sem ela cada deploy re-dropa patches]; (2) extração `Spx::Tozi::*` → `Spx::*` com a Tozi como 1º consumidor do motor genérico (prova por regressão); (3) onboarding kit v1 (runbook + scripts idempotentes — metade existe); (4) 2º cliente do MESMO vertical (valida o pack); (5) 1º cliente fora do vertical (prova a separação motor/pack). + specs nos fluxos críticos (hoje **zero** no código custom — risco R1 da auditoria de 04/06).

**Multiplicador:** replicar sem o meta-agente (6.6) não escala — cada cliente novo = horas de tuning manual. Com o loop de evals por conta, o tuning é o produto trabalhando sozinho: a Simplex vende resultado que melhora toda semana, não implantação.

---

## Sequência recomendada e dependências

```
O0 (11-12/06) ──► Reconciliação de branches (3-5 dias, trava tudo o resto)
                       │
        ┌──────────────┼────────────────┐
        ▼              ▼                ▼
   O1 Percepção   O2 Mãos          O4.1 Vigia SLA   ← paralelos, times diferentes
   (PDF + notas)  (atribuição)     (config, sem código)
        │              │
        ▼              ▼
   O3 Memória ◄────────┘   (perfil precisa das tools de escrita)
        │
        ▼
   O4 Proatividade ──► O5 Negócio (Vista fundo) ──► O6 Autocrítica ──► O7 Produto
```

**Regra de bolso de priorização** (vale para tudo que surgir no caminho): 1º o que o LEAD percebe (percepção, resposta certa), 2º o que o TIME percebe (atribuição, notas, notificação), 3º o que o GESTOR percebe (evals, painéis), 4º o que a SIMPLEX percebe (multi-cliente).

---

## Alinhamento com o planejamento comercial (Tozi - Planejamento de Projeto.pdf, mar/2026)

Status dos marcos contratados em 10/06/2026 (considerando a pausa pós-acidente e a migração de plataforma n8n→SPX, que NÃO estava no plano e foi feita em abr–jun):

| Marco | Data contratada | Status real | Onda que o cobre |
|---|---|---|---|
| M1 SDR Passivo (todos os deptos) | 10/04 | 🟡 go-live 11–12/06 (Vendas/Locação); Jurídico/Financeiro dependem do `consultar_cadastro` | O0 + O2 (deptos: O5) |
| M2 Follow-up automatizado | 08/05 | 🟢 **entregue e superado** (2 camadas nativas, em prod desde 29/05 — o plano previa só workflow n8n) | O0 ✅ |
| M3 BDR/SDR Ativo operando | 05/06 | 🟢 **em dia** — 7.249 HSM (02–08/06), 24,2% resposta, motor próprio | ✅ |
| M4 BDR estabilizado | 03/07 | 🟢 em curso (relatórios, A/B, saúde do número) — módulo de campanhas consolida | O. campanhas (plano-mestre F3) |
| M5/M6 VoxIA (voz) | 28/08 / 23/10 | ⚪ não iniciado (S17 só começa 06/07 — ainda no prazo) | **fora deste roadmap — frente própria** |
| MA Financeiro automatizado | 08/05 | 🔴 não iniciado (~1 mês de atraso) | O5 (consultar_cadastro/boleto é a porta de entrada) |
| MB Jurídico automatizado | 03/07 | ⚪ não iniciado (prazo ainda corre; leitura de contratos = O1.1 + O5) | O1 + O5 |
| MC Gestão com IA | 28/08 | ⚪ futuro | O6 (evals/painéis é a fundação) |

**Leitura honesta:** o atraso real é menor do que parece — M2 e M3 estão entregues (M2 melhor que o contratado), e o "atraso" do M1 comprou a migração inteira pra plataforma própria (multimodal nativa, follow-up nativo, sem dependência de n8n), que era pré-requisito invisível de TODO o resto do ciclo. As frentes verdadeiramente atrasadas: M1-deptos internos e MA (Financeiro) — ambas destravam pelo mesmo item: **integração Vista profunda (Onda 5)**.
