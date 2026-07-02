# Plano de Implementação — IA de Atendimento "Fábrica dos Óculos" no SPX

> **Status:** planejamento (kickoff 2026-06-24).
> **Base:** reaproveitamento do esqueleto de IA construído para a Tozi (modelo "IA como agente atribuível" + tools do Captain + funil/cadência + engine de campanhas).
> **Decisões travadas com o Paulo (24/06):** CRM externo (integrar) · poucas lojas (1+ por cidade) · agendamento de consulta = negociação com clínica parceira via proposta WhatsApp · catálogo de produtos vem de sistema/planilha/API externa.

---

## 1. Resumo do negócio e dos fluxos

A Fábrica dos Óculos trabalha com três linhas, com jornadas distintas:

| Linha | Jornada-alvo | Particularidade |
|---|---|---|
| **Óculos de sol** | Apresentar produto → cadastrar no CRM → agendar visita na loja mais próxima | Simples. Loja = ativo do próprio cliente. |
| **Relógios** | Idêntico aos óculos de sol | Simples. |
| **Óculos de grau — COM receita** | Apresentar armação → cadastrar no CRM → agendar visita na loja | Cliente já tem receita; vai direto à loja. |
| **Óculos de grau — SEM receita** | Qualificar → **agendar consulta numa clínica parceira (negociação)** → **levar o cliente até a clínica** → depois visita à loja para a armação | A Fábrica **não faz exame** — ela *embute* o serviço de agendar a consulta e o transporte. **É o fluxo novo e mais complexo.** |

**Insight central:** dois tipos de agendamento muito diferentes:
- **Visita à loja** (interno, baixa fricção — a loja é do cliente): IA registra a intenção + horário e notifica/atribui à loja.
- **Consulta na clínica** (externo, negociação a três pontas): IA envia uma **proposta** à clínica via WhatsApp ("Cliente com horário X. 1. Aceitar 2. Sugerir outro 3. Recusar"), recebe a resposta da clínica e **devolve ao cliente** para confirmar. Isso não existe na Tozi.

---

## 1.1 Atualização com dados reais do cliente (24/06) + deltas vs. plano inicial

> Insumos preenchidos pelo cliente/produção. Reescreve partes do plano abaixo. **A confirmar:** localização do fluxo atual e do `HANDOFF-PROJETO-ELEN`, e qual o ambiente-alvo do chatspx (ver §1.2).

**Identidade & canais**
- **Duas marcas, mesmo dono:** **Fábrica dos Óculos** (Sinop + Sorriso) e **Atacadão dos Óculos** (Cuiabá + Várzea Grande). **8 lojas** no total.
- **3 números WhatsApp Cloud API** (BSP hoje = **WTS Chat**; migração planejada para o chatspx): (66) 99979-1272 Fábrica · (65) 98121-0291 Atacadão Cuiabá · (65) 3362-3838 Atacadão Várzea Grande. **Roteamento por marca/cidade.** → no chatspx: 1 Account com **3 inboxes** (uma por número), agentes compartilhados.

**CRM = MTM (não genérico) + Acert**
- **MTM** = sistema interno próprio (Laravel + Voyager + MySQL), mantido pela própria Simplex. Lead entra via `POST /api/v1/clients`. **Identificação por CPF** (a IA consulta E cadastra por CPF — padrão NOVO, a Tozi não tinha). `MTM_API_KEY` já provisionado. HML: `fbchml.simplexsolucoes.com.br`.
- **Acert** = ERP (estoque/vendas), replicado no MTM.
- **Delta §8:** `registrar_no_crm` → **adapter do MTM por CPF** (`crm_sync_service` = MtmClient). Adicionar `buscar_cliente_por_cpf`.

**Catálogo: REMOVIDO do MVP**
- Decisão do cliente: preços/estoque mudam muito → a IA **NÃO cota produto ao vivo**; faz **triagem por conversa e leva o cliente à loja** para ver de perto.
- **Delta §8:** a tool `buscar_produto` **sai do escopo** (remove a integração de catálogo). Simplifica o plano.

**Lojas (8) — roteamento por proximidade, nunca por lista**
- Sinop (4): Nogueiras/matriz · Shopping · André Maggi · Pitangueiras. Sorriso (1). Cuiabá (2): CPA II · Pedra 90. Várzea Grande (1).
- A IA escolhe a **mais próxima** (cidade → desempate por lat/lng quando a cidade tem >1; Sinop e Cuiabá têm). **Nunca pede pro cliente escolher de uma lista.**
- Endereços/CEPs conhecidos (geocodar p/ obter lat/lng). Pendências: confirmar bairro da André Maggi, CEP da CPA II, endereço da Pedra 90.
- **Notificação de agendamento:** só a **gerente da loja** em questão — notificação **interna no próprio SPX** (não WhatsApp externo).

**Horário por loja (não global)**
- Padrão **seg–sáb 8h–18h**. **Exceção: loja Shopping = seg–sáb 10h–22h + dom 14h–20h.**
- **Delta §6/§8:** o `business_hours` e o gate de agendamento têm que ser **por loja**, não um valor fixo da conta.

**Clínicas (16 ativas) — broker VIÁVEL**
- Preço **por clínica** (R$ 70 a R$ 180; 4 "agregado" = consulta inclusa/R$ 0). Em regra o **cliente paga**; grátis só nas agregadas. Convênios: em aberto.
- **As clínicas respondem por WhatsApp** → o subsistema de proposta (§7) é viável de automatizar. **Sem resposta no prazo → escala para a gerente.**
- Cidade/WhatsApp/responsável de cada clínica = cadastrar quando a feature subir.

**Transporte = STORE-FIRST (muda o fluxo da consulta)**
- A Fábrica **leva o cliente até a clínica**: o **vendedor leva o cliente da loja à clínica**. Por isso o cliente é incentivado a **passar na loja antes** ("passa aqui que a gente te leva pra consulta").
- A IA **não agenda transporte**; **só avisa o responsável** — o transporte é organizado **na loja** quando o cliente chega.
- **Delta §5.3/§6:** o fluxo "grau sem receita" roteia o cliente **pela loja primeiro**, e a consulta fica amarrada a "passa na loja → vai pra clínica". O funil reflete isso.

**Tom & limites (sobrescreve a persona estilo-Tozi)**
- Tom: **simples e descontraído, "de casa", frases curtas, SEM emoji**, sem jargão. **Não força venda** (canal = descoberta + agendamento). Na dúvida, **passa pra humano** em vez de inventar.
- **NÃO pode:** dar desconto · prometer prazo de entrega · dizer que a consulta está "marcada" **antes da clínica confirmar** · analisar receita médica · falar de lente de contato ou cirurgia · iniciar conversa fora dos modelos aprovados (Meta).
- **Handoff para humano:** reclamação/defeito/garantia · cliente irritado · desconto/convênio · pedido não encontrado · fora de escopo (lente/cirurgia/análise de receita) · **alta intenção de compra** (marca/modelo/prazo/presente) · cliente fora do MT · não entendeu após 2 tentativas · falha técnica.
- **Atendimento:** seg–sáb 8h–18h (com a exceção da Shopping).

**Equipe de agentes (revisada p/ este negócio)**
- **Recepção/Triagem** (identifica linha + pega CPF, consulta MTM) → **Sol & Relógios** (triagem → leva à loja) · **Óculos de Grau** (COM receita → loja; SEM receita → broker de clínica + store-first).

## 1.2 Estado do ambiente (verificado read-only 24/06) — A CONFIRMAR

- O servidor `3.87.182.184` (host `ip-172-31-83-31`) está com o **código de produção da Tozi** (branch `producao`, HEAD `5170569e2`); `app/services|jobs|listeners/spx` só tem `tozi`. **Sem MTM, sem `fabrica_oculos`, sem vault, sem `HANDOFF-PROJETO-ELEN`.**
- IP difere do registrado pra Tozi no STATE.md (`3.82.215.109`) com código idêntico → provável **clone da Tozi como base de build da Fábrica**, ou Tozi prod em IP novo.
- **Hipótese de trabalho:** o **fluxo atual roda no WTS Chat (BSP)** + API do MTM; o chatspx é o **alvo da migração** (greenfield sobre o esqueleto Tozi). MTM = integração a **construir**, não código a portar.
- **Bloqueios de confirmação:** (1) obter o `HANDOFF-PROJETO-ELEN` e docs do fluxo atual; (2) confirmar se este box é o ambiente-alvo e o papel do `fbchml.simplexsolucoes.com.br`; (3) confirmar que o fluxo vive no WTS Chat.

---

## 1.3 Integração MTM (API mapeada 25/06) + abordagem de tools

**Doc:** `https://fabrica.simplexsolucoes.com.br/api-docs` · Base: `…/api/v1` · Auth: `Authorization: Bearer <MTM_API_KEY>`.

> **Descoberta-chave:** o MTM é o **sistema de registro de tudo** (clients, shops, clinics, appointments, checkups/vision-tests, sellers/user-shops, products/stocks via Acert, messaging-templates) e **foi desenhado já com o fluxo da Elen**: `clinics` tem `contato_whatsapp_e164`, `sla_resposta_min`, `valor_consulta`, `formas_pagamento`, `lat/lng`, `horario_funcionamento`; `appointments` tem `clinic_id` **e `proposal_id`** + `vision_test_id`/`checkup_id`. Visita à loja vs consulta se distingue pelo **`clinic_id`** presente.

**Mapa tool → MTM:**

| Tool (Elen) | Método | Endpoint | Campos-chave |
|---|---|---|---|
| `buscar_cliente` | GET | `/clients?cpf=` | filtro exato por `cpf` (e `cidade`,`status`) |
| `registrar_cliente` | POST | `/clients` | `razao_social`(nome), `cpf`, `fone1`, `cidade`, `bairro`, `endereco`, `cep`, `status` |
| `listar_clinicas` | GET | `/clinics?ativo=true` | `nome`, `endereco_cidade`, `contato_whatsapp_e164`, `valor_consulta`, `sla_resposta_min`, `lat/lng` |
| `loja_por_cidade` | GET | `/shops?departamento=&cidade=` | `departamento`(fabrica/atacadao), `cidade`, `bairro`, `nome_exibicao` — **sem lat/lng** |
| `agendar` (visita/consulta) | POST | `/appointments` | **obrig.:** `time`,`shop_id`,`seller_id`; opc.: `client_id`/`cpf`, `clinic_id`(→consulta), `proposal_id`, `obs` |

**Abordagem de build:**
- **Custom tools (config no banco, SEM deploy):** `buscar_cliente`, `registrar_cliente`, `listar_clinicas`, `loja_por_cidade`, `agendar` — todas GET/POST, `auth_type: bearer`, `auth_config` guarda a `MTM_API_KEY`. `param_schema` + `request_template`/`response_template`. (`Captain::CustomTool` valida endpoint contra SSRF — domínio público passa.)
- **Built-in (código, deploy):** `loja_mais_proxima` — Haversine sobre um **mapa estático de lat/lng das 8 lojas** (o MTM `/shops` não tem coords) + localização do cliente (pin ou CEP). Só necessária para cidades com >1 loja (Sinop 4, Cuiabá 2); demais cidades = roteamento direto por `cidade`+`departamento`.

**Itens abertos do contrato (pequenos):**
- **`seller_id` é obrigatório no `/appointments`** — definir qual vendedor a IA usa (um "vendedor IA/online" por loja? a gerente? round-robin?).
- **`proposal_id`** referencia uma proposta — confirmar se há recurso `/proposals` (broker de clínica já modelado no MTM?) ou se é id gerado no chatspx.
- **`MTM_API_KEY`** (valor do Bearer) — não está no `.env` do box ainda; obter para ativar as tools.

---

## 2. Como isso vive dentro do SPX

A Fábrica dos Óculos é um **novo tenant** (Account) no mesmo SPX, exatamente como a Tozi convive com os outros clientes do SaaS. Nada do esqueleto é jogado fora; o que é específico de cliente ganha um **namespace próprio** `Spx::FabricaOculos::*`, espelhando `Spx::Tozi::*`.

```
SPX (fork Chatwoot)
├── Account: "Fábrica dos Óculos"            ← novo tenant
│   ├── Inbox WhatsApp Cloud API (clientes)  ← número oficial da Fábrica
│   ├── Inbox "Clínicas Parceiras"           ← canal de negociação com clínicas (ver §7)
│   ├── Agentes IA (Captain::Assistant + espelho AgentBot bot_type:captain)
│   │   ├── Recepção/Triagem
│   │   ├── Sol & Relógios
│   │   └── Óculos de Grau
│   ├── Funil "Atendimento Óptica"           ← Kanban por estágio
│   └── Knowledge base (Q&A + docs curados)
│
├── Genérico reutilizado AS-IS (zero mudança):
│   ├── Modelo "IA como agente atribuível"   (mirror + AssignmentKickJob + reset_agent_bot…)
│   ├── Behavior services (router/debounce/business_hours/humanizer/dedup/copilot)
│   ├── Tools genéricas (transferir_para_agente, programar_followup, handoff, notas, RAG)
│   ├── Funil/Kanban (Funnel/FunnelStage/FunnelItem)
│   └── Engine de campanhas (Campaign + CampaignRecipient + DispatchSchedulerJob)
│
├── Adaptado por cópia (mude constantes/templates):
│   ├── Spx::FabricaOculos::FunnelPlacementService      ← copia Tozi
│   ├── Spx::FabricaOculos::FunnelAutomationListener    ← copia Tozi
│   └── Spx::FabricaOculos::ReactivationCadenceService  ← copia Tozi (templates novos)
│
└── NOVO (construir):
    ├── BuscarProdutoTool            ← catálogo externo (adapter)
    ├── RegistrarNoCrmTool           ← CRM externo (adapter)
    ├── LojaMaisProximaTool          ← diretório de lojas por cidade
    ├── AgendarVisitaLojaTool        ← registra intenção + notifica loja
    ├── SolicitarConsultaClinicaTool ← dispara a negociação com a clínica
    └── Subsistema de proposta a clínicas (ConsultaProposal + relay + state machine)
```

**Por que "IA como agente atribuível":** é o modelo já validado na Tozi. Cada agente é um `Captain::Assistant` com um `AgentBot` espelho (`bot_type: :captain`). A IA só responde a conversa **atribuída a ela**; atribuir um humano zera o bot automaticamente (`reset_agent_bot_when_assignee_present`) = "humano assume → IA cala" de graça. Transferência IA→IA é invisível (`transferir_para_agente`). **Já existe e é genérico — herdamos inteiro.**

---

## 3. Mapa de reuso (genérico × adaptar × novo)

| Componente | Caminho (referência) | Veredito |
|---|---|---|
| Modelo IA-como-agente (espelho, kick, exclusividade) | `enterprise/app/services/captain/assistant_mirror_service.rb`, `…/assignment_kick_job.rb`, `app/models/conversation.rb` | ✅ **AS-IS** |
| Behavior services (6/7 puros) | `enterprise/app/services/captain/behavior/*.rb` | ✅ **AS-IS** (só configurar JSONB) |
| Tools genéricas | `enterprise/lib/captain/tools/{transferir_para_agente,programar_followup,handoff,add_*_note,faq_lookup,search_knowledge,resolve_conversation}_tool.rb` | ✅ **AS-IS** |
| Funil/Kanban | `app/models/{funnel,funnel_stage,funnel_item}.rb` | ✅ **AS-IS** |
| Engine de campanhas (Fase 0/2a) | `app/models/campaign*.rb`, `app/services/campaigns/whatsapp/*`, `app/jobs/campaigns/whatsapp/dispatch_scheduler_job.rb` | ✅ **AS-IS** (genérico, dirigido por template) |
| Registro de tools | `config/agents/tools.yml` + `Captain::Assistant#configured_agent_tools` | ✅ **AS-IS** (só adicionar entradas) |
| FunnelPlacementService | `app/services/spx/tozi/funnel_placement_service.rb` | 🟡 **COPIAR** → `Spx::FabricaOculos::*` (trocar estágios) |
| FunnelAutomationListener | `app/listeners/spx/tozi/funnel_automation_listener.rb` | 🟡 **COPIAR** (ajustar transições) |
| ReactivationCadenceService | `app/services/spx/tozi/reactivation_cadence_service.rb` | 🟡 **COPIAR** (templates novos) |
| salvar_info_lead | `enterprise/lib/captain/tools/salvar_info_lead_tool.rb` | 🟡 **GENERALIZAR** (hoje chama `Spx::Tozi::*` direto — extrair p/ config por conta) |
| Haversine/proximidade | `enviar_localizacao_tool.rb` (`haversine_km`) | 🟡 **REAPROVEITAR** o algoritmo, nova fonte (lojas) |
| BuscarImovelTool / EnviarFotosImovelTool / enviar_localizacao (Tozi) | Vista API, coords Tozi | ❌ **NÃO** (específico Tozi) — servem só de molde |
| DisparoLeadJob (Tozi) | `app/jobs/spx/tozi/disparo_lead_job.rb` | ❌ **NÃO** — usar a **engine de campanhas genérica** no lugar |

> A engine de campanhas genérica (commits `0967e95c3` + `21929abe9`) é o caminho para qualquer disparo da Fábrica — **não** replicar o `DisparoLeadJob` hardcoded.

---

## 4. Equipe de agentes IA

Time enxuto, no modelo IA-como-agente (cada um atribuível + espelho):

| Agente | Papel | Tools principais |
|---|---|---|
| **Recepção** (triagem) | Abre, identifica a linha (sol/relógio/grau) e a intenção; transfere. Não vende, não busca. | `transferir_para_agente`, knowledge institucional |
| **Sol & Relógios** | Apresenta produto, qualifica, cadastra no CRM, agenda visita à loja mais próxima. | `buscar_produto`, `registrar_no_crm`, `loja_mais_proxima`, `agendar_visita_loja`, `programar_followup`, `enviar_localizacao_loja` |
| **Óculos de Grau** | Bifurca COM/SEM receita. COM → visita à loja. SEM → dispara consulta na clínica + organiza transporte. | tudo do Sol/Relógios **+** `solicitar_consulta_clinica` |
| **(backend) Coordenação Clínicas** | *Opcional na Fase 2.* Conversa com as clínicas, lê a resposta (Aceitar/Sugerir/Recusar) e devolve ao cliente. | tools de relay (§7) |

> Recomendação: começar com **3 agentes voltados ao cliente** (Recepção, Sol/Relógios, Grau). A coordenação com a clínica entra primeiro **com humano no loop** (Fase 1) e vira agente/automação plena na Fase 2.

A triagem de entrada reusa o padrão da Tozi (automation `assign_ai_agent` em `conversation_created` → Recepção responde → transfere por intenção).

---

## 5. Fluxos detalhados (passo a passo + tools que disparam)

### 5.1 Óculos de sol / Relógio
1. Lead chega → **Recepção** identifica "sol/relógio" → `transferir_para_agente` → **Sol & Relógios**.
2. Qualifica (modelo, estilo, faixa de preço) → `buscar_produto` (catálogo externo) → apresenta opções.
3. Interesse → `registrar_no_crm` (lead + produto de interesse) → `loja_mais_proxima` (por cidade do cliente).
4. `agendar_visita_loja` (registra preferência de horário, notifica/atribui à loja) → `enviar_localizacao_loja` (pin).
5. Sem fechamento → `programar_followup`. Estado no funil acompanha (§6).

### 5.2 Óculos de grau — COM receita
Igual ao 5.1, com o **Óculos de Grau**: confirma que tem receita → `buscar_produto` (armações) → `registrar_no_crm` → `agendar_visita_loja`. A receita pode ser anexada (foto) e salva na ficha.

### 5.3 Óculos de grau — SEM receita ⭐ (fluxo novo)
1. **Óculos de Grau** confirma que **não tem receita** → explica que a Fábrica **agenda a consulta e leva o cliente até a clínica** (serviço embutido).
2. Coleta: cidade/região, dias/horários de disponibilidade, convênio (se aplicável) → `registrar_no_crm`.
3. `solicitar_consulta_clinica` → escolhe a(s) clínica(s) parceira(s) da cidade → **subsistema de proposta** (§7) envia à clínica a mensagem com botões **Aceitar / Sugerir horário / Recusar**.
4. Clínica responde:
   - **Aceitar** → confirma horário ao cliente → marca consulta + organiza transporte (`agendar_transporte`/nota p/ logística) → depois encaminha para a visita à loja (armação).
   - **Sugerir outro horário** → devolve a sugestão ao cliente → confirma/loop.
   - **Recusar** → tenta a próxima clínica da cidade ou pede novos horários ao cliente.
5. Cliente fica "quente" no funil em `aguardando_clinica` até confirmar; cadência de follow-up evita lead parado.

---

## 6. Funil "Atendimento Óptica" (Kanban)

Estágios sugeridos (criados por rake, `automation_type`-driven — tunável):

```
novo_lead → triagem → produto_apresentado
   ├─(sol/relógio/grau c/ receita)→ visita_agendada → em_loja → convertido
   └─(grau s/ receita)→ aguardando_clinica → consulta_agendada → visita_agendada → convertido
                                                                    └→ frio/perdido
```

Movimento automático via `Spx::FabricaOculos::FunnelAutomationListener` (cópia do listener da Tozi): incoming → triagem/em_conversa; `agendar_visita_loja` → visita_agendada; `solicitar_consulta_clinica` → aguardando_clinica; clínica aceita → consulta_agendada; handoff/compra → convertido; esfriou → frio + cadência HSM.

---

## 7. ⭐ Subsistema novo: proposta/negociação com clínicas

**O ponto mais arriscado do projeto. Não existe na Tozi.** É um *broker assíncrono a três pontas* sobre WhatsApp.

### 7.1 Entidades
- **`ConsultaProposal`** (modelo novo): liga `customer_conversation_id` ↔ `clinic_contact_id`/`clinic_conversation_id`, guarda `requested_slots` (janelas de horário), `status` (`draft → sent → accepted/suggested/declined → confirmed/cancelled`), `proposed_slot`, `waba_message_id` (da proposta) e `account_id`.
- **Diretório de clínicas parceiras** por cidade (tabela `fabrica_oculos_clinics`: nome, cidade, telefone WhatsApp, lat/lng opcional, ativo).
- **Inbox "Clínicas Parceiras"** (ou contatos dedicados) — separa a conversa clínica da conversa cliente, com persona/agente próprios (não o agente que fala com o cliente).

### 7.2 Mensagem à clínica (com botões)
HSM transacional (utility) aprovado, ex. `fab_clinica_proposta`, com **3 botões quick-reply**: `Aceitar` · `Sugerir horário` · `Recusar`.
> Corpo: "Olá {{1}}! Temos um cliente para consulta. Região {{2}}, disponibilidade {{3}}. Podemos confirmar?"
> `Sugerir horário` → abre a janela de 24h e a clínica digita o horário em texto livre (a IA/coordenação interpreta).

### 7.3 Correlação da resposta (o detalhe técnico crítico)
Quando a clínica responde, o sistema precisa saber a qual proposta/cliente pertence. Estratégia recomendada (robusta + simples):
1. **Serializar:** no máximo 1 `ConsultaProposal` ativa por clínica por vez (fila). A resposta cola na proposta ativa daquela conversa.
2. **Reforço:** guardar o `waba_message_id` da proposta e casar com o `context.id` da resposta de botão quando o WhatsApp o entregar (a confirmar na Cloud API — quick-reply carrega contexto da mensagem citada).
3. **Fallback humano:** ambiguidade → cai para um humano da coordenação resolver (sempre presente como rede de segurança).

### 7.4 Relay de volta ao cliente
Tool `responder_consulta_ao_cliente(proposal_id, outcome, details)`: reabre/atualiza a conversa do cliente e o **Óculos de Grau** comunica o resultado (confirmado / nova sugestão / tentar outra clínica). Mantém o tom do agente do cliente, sem vazar a conversa com a clínica.

### 7.5 "Levar o cliente até a clínica" (transporte)
Serviço embutido. Na confirmação: criar tarefa/nota de logística (`agendar_transporte`), registrar no CRM, opcionalmente enviar pin da clínica ao cliente. MVP = captura + handoff para logística; automação plena depois.

### 7.6 Fasear o broker (recomendação)
- **Fase 1 (MVP):** IA conduz 100% o lado do cliente; do lado da clínica a IA **monta e dispara a proposta**, mas um **humano supervisiona a resposta** da clínica e confirma o relay. Risco controlado.
- **Fase 2:** `ConsultaProposal` + interpretação automática dos botões + relay automático + retries/fallback. Coordenação vira agente.

---

## 8. Tools novas a construir (assinaturas)

Todas herdam `enterprise/lib/captain/tools/base_public_tool.rb` e são registradas em `config/agents/tools.yml` + listadas em `assistant.config['tools']`.

| Tool | Fonte de dados | Esboço de parâmetros |
|---|---|---|
| `buscar_produto` | Catálogo externo (sistema/planilha/API — **definir**) | `categoria` (sol/relógio/armação), `marca?`, `faixa_preco?`, `genero?` → retorna até N itens c/ foto/link |
| `registrar_no_crm` | CRM externo (**definir qual**) | `nome`, `telefone`, `interesse`, `cidade`, `status`, `origem` → cria/atualiza lead via adapter |
| `loja_mais_proxima` | Diretório de lojas (por cidade; lat/lng se cidade tiver >1) | `cidade`/`coordenadas` → loja(s) + distância (Haversine reaproveitado) |
| `agendar_visita_loja` | Interno (funil + notificação) | `loja_id`, `preferencia_horario`, `produto` → registra intenção, move funil, notifica loja |
| `enviar_localizacao_loja` | Diretório de lojas | `loja_id` → pin nativo (molde = `enviar_localizacao_tool`) |
| `solicitar_consulta_clinica` | Diretório de clínicas + subsistema §7 | `cidade`, `disponibilidade`, `convenio?` → cria `ConsultaProposal`, dispara proposta |
| `responder_consulta_ao_cliente` | `ConsultaProposal` | `proposal_id`, `outcome`, `details` → relay ao cliente |
| `agendar_transporte` | Interno (nota/tarefa logística) | `proposal_id`/`conversa`, `endereco_cliente`, `horario` |

**Reaproveitadas as-is:** `transferir_para_agente`, `programar_followup`, `handoff`, `add_contact_note`, `add_private_note`, `faq_lookup`, `search_knowledge`, `resolve_conversation`.
**Generalizar:** `salvar_info_lead` (hoje acopla `Spx::Tozi::*` — extrair o "qual cliente" para config por conta, para servir Tozi **e** Fábrica).

---

## 9. Camada `Spx::FabricaOculos::*` a criar

Espelhando `Spx::Tozi::*`:
- `app/services/spx/fabrica_oculos/funnel_placement_service.rb`
- `app/listeners/spx/fabrica_oculos/funnel_automation_listener.rb`
- `app/services/spx/fabrica_oculos/reactivation_cadence_service.rb`
- `app/services/spx/fabrica_oculos/crm_sync_service.rb` (adapter do CRM externo)
- `app/services/spx/fabrica_oculos/clinic_proposal_service.rb` (orquestra §7)
- `app/models/consulta_proposal.rb`, `app/models/fabrica_oculos/{store,clinic}.rb`
- `lib/tasks/spx_fabrica_oculos.rake` (`setup_funnel`, `create_templates`, `seed_stores`, `seed_clinics`)
- Migrations: `consulta_proposals`, `fabrica_oculos_stores`, `fabrica_oculos_clinics`

> **Enterprise overlay:** tools/comportamentos do Captain vivem sob `enterprise/`. Antes de editar qualquer lógica core, conferir as duas árvores (`rg "Foo" app enterprise`) — regra do projeto.

---

## 10. Roadmap em fases (com critério de pronto)

| Fase | Entrega | Critério verificável |
|---|---|---|
| **F0 — Infra/tenant** | Account criada, inbox WhatsApp Cloud API ligada, chaves LLM, knowledge inicial, funil via rake | Mensagem de teste entra na inbox; agente responde em sandbox; funil aparece no Kanban |
| **F1 — Agentes + venda + visita à loja** | 3 agentes (Recepção/Sol-Relógios/Grau), `buscar_produto`, `registrar_no_crm`, `loja_mais_proxima`, `agendar_visita_loja`; broker de clínica **com humano no loop** | E2E: lead de óculos de sol → produto → CRM → visita agendada. Grau s/ receita → proposta enviada à clínica (humano confirma) |
| **F2 — Broker de clínica pleno** | `ConsultaProposal` + botões interpretados + relay automático + retries/fallback + transporte | E2E: clínica clica "Aceitar" → cliente recebe confirmação automática; "Sugerir" e "Recusar" tratados |
| **F3 — Campanhas + cadência** | Engine de campanhas genérica plugada + `ReactivationCadenceService` (HSM 1d/3d/7d) | Disparo de teste sai com pacing/health-gate; lead frio recebe cadência |
| **F4 — Go-live faseado** | Piloto whitelist → abertura geral, monitoramento + rollback | Piloto com N números reais sem incidente; flip controlado |

Esforço aproximado (depende dos insumos de §11): **F0** ~0,5–1 dia · **F1** ~3–5 dias · **F2** ~3–5 dias (o mais incerto) · **F3** ~1–2 dias (engine pronta) · **F4** faseado.

---

## 11. Insumos necessários do cliente (bloqueiam partes do plano)

1. **CRM:** qual é (RD Station / Pipedrive / Bitrix / planilha / outro), tem API/webhook, e mapeamento de campos. → desenha `registrar_no_crm` + `crm_sync_service`.
2. **Catálogo de produtos:** que sistema/planilha/API, com que campos (categoria, marca, preço, foto, disponibilidade) e credenciais. → desenha `buscar_produto`.
3. **Lojas:** lista com cidade, endereço e (onde houver >1 por cidade) lat/lng. → `loja_mais_proxima` + pins.
4. **Clínicas parceiras:** lista por cidade, **número de WhatsApp**, e — crítico — **elas topam responder por botão/WhatsApp?** Há contato responsável? → viabilidade do broker (§7).
5. **Transporte:** como funciona hoje (frota própria, parceiro, app)? A IA agenda ou só sinaliza? → `agendar_transporte`.
6. **WhatsApp:** número(s) Cloud API oficial(is) — um para clientes; decidir se clínicas usam o mesmo número ou inbox separada. Aprovação dos HSM (proposta à clínica, follow-up, reativação).
7. **Conteúdo:** material para a knowledge (institucional, linhas de produto, política de receita, como funciona o serviço de consulta+transporte, objeções).

---

## 12. Riscos e mitigações

- **Broker de clínica (maior risco):** parceiros podem não responder por botão / demorar / responder fora do padrão. → Fase 1 com humano no loop; serializar propostas; TTL + fallback humano; medir taxa de resposta das clínicas antes de automatizar.
- **CRM externo instável/limitado:** → adapter isolado (`crm_sync_service`) com fila/retry; degradar para registro no SPX se o CRM cair.
- **Catálogo externo:** latência/limites de API → cache curto; fallback para catálogo curado na knowledge.
- **Acoplamento do `salvar_info_lead` à Tozi:** generalizar antes de reusar para não quebrar a Tozi (contrato OSS↔Enterprise estável).
- **Multi-tenant:** nada hardcoded de conta no OSS; comportamento por conta via config/feature flags (regra do projeto).

---

## 13. Próximos passos sugeridos

1. Coletar os 7 insumos da §11 (posso montar um formulário/checklist para o cliente).
2. Fechar a **viabilidade do broker de clínica** (item 4) — é o que define se F2 é automação plena ou assistida.
3. Aprovar este plano → eu inicio a **F0** (criar tenant + inbox + funil + 1 agente em sandbox) para um E2E rápido.
4. Onboardar a Fábrica dos Óculos no vault SimplexOB (nota de cliente) quando os dados firmarem.

> Reaproveitamento estimado do esqueleto Tozi: **~70% do trilho** (modelo IA-como-agente, behaviors, funil, campanhas, follow-up, transferência IA→IA). O esforço real concentra-se nas **tools de integração** (catálogo + CRM) e no **broker de clínicas** (subsistema novo).
