# Rodízio e Atribuição (Tozi): Brainstorm / Discovery Notes

Date: 2026-07-30 · Goal: extrair do Paulo as regras de negócio do rodízio/atribuição pra fechar a spec da máquina de estados — antes de escrever código.

Frente: `spx/rodizio` (worktree `chatspx-frentes/rodizio`) · Papel: executora

---

## Contexto técnico já levantado (leitura de código, 30/07 — não perguntar ao Paulo)

**O motor F1 de distribuição JÁ EXISTE e já está ligado.** O `CLAUDE.local.md` da frente estava desatualizado nesse ponto.

| Peça | Onde | Estado |
|---|---|---|
| `Spx::Distribuicao::DistribuirService` | `app/services/spx/distribuicao/distribuir_service.rb` | ✅ pronto: continuidade → rodízio (ponteiro) → `sem_pool`, com cap e log |
| Tabelas `distribuicao_policies` / `_states` / `_logs` | migration `20260701150000` | ✅ migradas |
| Gancho no handoff | `Captain::Conversation::HumanHandoffService#perform` | ✅ chama o `DistribuirService` |
| `resolve_team` | mesmo arquivo | ✅ **ligado** (não é fix parqueado) |
| `so_online` | coluna existe em `distribuicao_policies` | ⚠️ **parqueado** — o serviço ignora |
| `modo: 'online'` | aceito pelo `Policy` | ⚠️ não implementado no serviço (cai em no-op) |

**Origem:** `docs/clientes/tozi/MOTOR-DISTRIBUICAO.md` (kickoff 01/07, pedido do Guilherme por áudio — "a Maria distribui na mão, tem que ser automático, compulsório e configurável").

### O nó central (confirmado no código)

Hoje há **dois** modelos brigando, e nenhum é o desta frente:

| Modelo | Dono | IA responde? | SLA conta de |
|---|---|---|---|
| **Pull** — `aguardando_humano_desde`, aba "Aguardando atendimento" | IA segue dona | ✅ sim | quando o humano **puxa** ← o problema do Guilherme |
| **Push** — rodízio (hoje) | humano, na hora | ❌ **cala na hora** | da atribuição |

Ponto exato do "cala": `DistribuirService#assign!` → `Conversations::AssignmentService` → callback `before_validation :reset_agent_bot_when_assignee_present` (`app/models/conversation.rb:370`) zera `assignee_agent_bot_id`. Todo o pipeline do Captain gateia nesse campo (`captain_listener.rb:19`, `debounced_response_job.rb:16`).

→ **Designar = calar**, mesmo que o corretor só abra a conversa 40 min depois. O terceiro estado ("designado, ainda não assumido") tem que separar **"tem dono"** de **"o dono assumiu"** sem derrubar o espelho captain.

### Peças correlatas já existentes
- `Conversations::TakeoverGate` + `TakeoverRequestService` (flag `takeover_request_gate`) — pedido/aprovação de atendimento, isolamento por agente.
- `Spx::Distribuicao::Policy` — política **por time**, opt-in (sem política = no-op).

### ⚠️ Achados de infraestrutura (30/07) — resolver ANTES de codar

**1. Esta worktree está 45 commits ATRÁS da `origin/homologacao`.**
- `spx/rodizio` = `6ef8340e5` · `origin/homologacao` = `a75b08c54` · **45 commits de delta**, e **zero commits próprios** da frente (`origin/homologacao..HEAD` vazio).
- O `CLAUDE.local.md` diz que a branch "nasceu de `origin/homologacao`" — nasceu, mas a homologacao andou desde então.
- ✅ **O mapa desta entrevista continua válido:** `distribuir_service.rb`, `human_handoff_service.rb`, `conversation.rb` e `policy.rb` estão **idênticos** nas duas pontas (verificado com `git diff`).
- **Ação:** `git merge --ff-only origin/homologacao` antes da primeira linha de código. Não bloqueia o design.

**2. `Spx::TemplateReplyRouterListener` EXISTE — mas não nesta worktree.**
- O `CLAUDE.local.md` o lista em "Peças que JÁ existem (não reinventar)". Ele **não está no HEAD desta branch**, e por isso não apareceu nas primeiras buscas.
- Está na `homologacao`, `producao`, `spx/eval`, `spx/campanhas`, `spx/followup`, `spx/fricoes` — só falta aqui, por causa do achado 1. Chega junto com o sync.
- Commit `7e48e36ca` (23/07), `app/listeners/spx/template_reply_router_listener.rb`, 79 linhas. Comportamento, direto da mensagem do commit:
  - **Template manual (sender User)** → conversa vai pro **humano que enviou**.
  - **Template de disparo/remarketing (sem sender + label rmkt)** → vai pra **IA configurada**, que decide se o cliente fala do template ou de outro assunto.
  - **Desarma sozinho** quando alguém já respondeu depois do template.
  - **Opt-in por conta** via `settings['template_reply_routing']` (zero efeito nos demais tenants).
- 👉 **Isso já implementa duas das três exceções** que o `CLAUDE.local.md` pede desta frente (template manual 1:1 fica com quem mandou · disparo/RMKT que muda de assunto vai pra IA). Confirmar no código pós-sync antes de desenhar exceção nova.

---

## Summary / key decisions

1. **A IA é extensão do atendimento, não etapa.** Ela nunca anuncia o handoff. Nada de "vou chamar um consultor" / "segunda-feira alguém te procura". O handoff pode acontecer **antes** de ela dizer qualquer coisa — é um evento interno, invisível pro cliente.
2. **Na janela "designado → assumido" a IA continua atendendo**, sem forçar: não puxa assunto, mas se o cliente engaja ela vai levando (papo despretensioso, informação, qualificação). Caso-canônico: fim de semana.
3. **O que trava a IA é ASSUMIR** (ação explícita do atendente) — não a primeira mensagem dele, não abrir a conversa. *(Corrige a proposta inicial do Claude, que era "primeira mensagem".)*
4. ~~**Representação do estado:** o terceiro estado é a combinação dos dois campos existentes (`assignee_id` + `assignee_agent_bot_id` vivos ao mesmo tempo); "Assumir" zera o espelho.~~ **🚫 REVOGADO na Q7 pelo Paulo.** Ver decisão 4-bis.
   - **4-bis (VALE ESTA): DESIGNAÇÃO É ESTADO DE PRIMEIRA CLASSE, e em vendas NÃO se seta `assignee`.**
     - `assignee` significa **"humano dono dentro do SPX"** — em vendas isso é **falso hoje**, e forçar o campo seria mentira no dado.
     - **Designado ≠ assumido.** A designação vive no **`Spx::Distribuicao::State` / `Log`** (que já existem), com corretor, timestamp, política aplicada e histórico.
     - **Zero mudança no `reset_agent_bot_when_assignee_present`.** Como `assignee` fica nulo, o callback nunca dispara, o espelho captain sobrevive e **a IA continua falando sem precisar de nenhuma alteração de código.**
     - **Nada de `custom_attribute` como fonte da verdade** — ele é só espelho de leitura (ver decisão 7).
     - 💡 **Consequência boa:** o "trabalho pesado de código" que o `CLAUDE.local.md` previa (brigar com o callback de exclusividade) **evapora**. O trabalho real vira: designação como estado de 1ª classe + espelho Vista + carimbo de contexto + tela de medição do gestor.
5. ~~**"Aguardando atendimento" vira caixa pessoal do designado.**~~ **⏸️ ESTACIONADO na Q7.** Depende de `assignee` setado, que a v1 (vendas) não faz. Volta a valer quando os corretores entrarem no **app nativo** — aí a transição "assumir" promove designação → `assignee`. Continua válido em tese pros times que já vivem dentro do SPX (que não são escopo da v1).
6. **A transição "assumir" é ADIÇÃO, não migração.** Quando o app nativo chegar, a única coisa nova é: promove designação → `assignee` e cala a IA. **Designação, contagem, SLA e política não mudam.**
7. **Carimbo de contexto (requisito de código pra conduta existir):** a designação é carimbada na conversa como **custom attribute**, pelo mesmo caminho por onde já entram `meta_campanha` / `meta_imovel` (`CustomAttributeDefinition` + `stamp_*`). Fonte da verdade = `Spx::Distribuicao::State`; o custom attribute é **só espelho de leitura pro turno do agente**. Sem isso o gatilho não fica visível pro LLM e a conduta "modo contido" não tem como existir.
8. **O sinal de "pode calar" NÃO é desta frente.** A **`spx/eval`** vai construir o **poll do Vista**: card mudou de etapa = corretor engajou → Sofia silencia. **Consumir o campo, não construir outro leitor.**
9. **Escopo da v1 = SÓ VENDAS.** Locação e administrativo **já rodam hoje** com o motor distribuindo e a IA calando. **Não mexer no que funciona.**
10. **Espelho do Vista nasce atrás de flag por time** (`espelho_vista: true/false` na policy), **nunca hardcoded** — desligar o paliativo tem que ser configuração, não deploy.
6. **⛔ RESTRIÇÃO PERMANENTE — nenhum número mágico no código.** Toda nuância (tempos de SLA, o que conta como recebido, destino do pool esgotado, janela de continuidade, punição) é **configurável por time**, na `distribuicao_policies`. O que discutimos nesta entrevista são os **defaults de fábrica da Tozi**, não constantes. Corolário de graça: como a política é **por time**, "regras por setor" (locação × vendas × administrativo) sai estruturalmente — é uma policy por time, não um `if` por setor.

---

## Q&A log

### Q1 — Comportamento da IA na janela "designado, ainda não assumido"

- **Asked:** com o rodízio apontando o Bruno e ele ainda sem abrir a conversa, a Sofia continua atendendo normal? E o que encerra o estado — primeira mensagem do corretor, ou clicar "assumir"?
- **Captured:**
  - Resposta **A, com correção de enquadramento**: *"queremos que a IA seja uma extensão do atendimento, não uma etapa"*. Portanto **o handoff pode acontecer antes mesmo da IA dizer que chamou um atendente**.
  - **Proibido anunciar:** *"não faz sentido ela falar que vai chamar um atendente ou dizer que segunda-feira alguém entra em contato"*.
  - **Tom na janela:** *"ela pode ficar ali, batendo um papo despretensioso com o cliente, lógico, não forçar a conversa, mas caso o cliente engaje ela pode ir atendendo"*.
  - **Cenário que motiva:** fim de semana — cliente já deu boas informações do que deseja, IA segue conversando.
  - Resposta **C** sobre o encerramento: **assumir a conversa trava a IA** (ação explícita, não a mensagem).
  - **Pergunta devolvida pelo Paulo (design, não negócio):** como isso fica **visível** no SPX? Histórico dos campos de atribuição: eram **3** (IA · atendente · time) → hoje são **2** (um campo IA/Atendente + um de time). Ele quer que *"a IA esteja com uma conversa, ao fazer o handoff ela continua falando mas o SPX todo se comporta como se aquele atendente já pudesse ver a conversa em 'aguardando atendimento'"*.
- **Flags:** nenhuma.

### Q2 — Handoff fora do horário comercial: designa na hora ou segura até abrir o expediente?

- **Asked:** Sofia dá handoff sábado 10h, ninguém trabalha até segunda 8h. Designa o corretor na hora (relógio de SLA só corre segunda) ou segura a designação até segunda?
- **Captured:**
  - **Designa na hora.** Confirmado.
  - Reforço (2ª vez) da regra de ouro do anúncio: **não** é *"vou chamar um atendente pra você, mas como estamos fora do horário comercial, na segunda-feira ele entra em contato"*.
  - *"É natural, fazer handoff e quando realmente for momento de falar que um consultor/corretor vai entrar em contato."*
  - → **Distinção importante pra spec:** o **handoff** é um evento **de sistema, silencioso**. O **anúncio** ("um consultor vai te procurar") é uma **decisão conversacional da IA**, tomada quando for o momento natural — os dois são **desacoplados** e podem acontecer com horas/dias de distância.
  - → **Delimitação de onde isso mora:** o anúncio é **conduta de prompt** (banco da conta 6, via Almirante `ai_update_prompt`), **não** código. O código só garante que o handoff não force nem bloqueie nada dito ao cliente.
- **Flags:** definir *quando* é "o momento natural" do anúncio → conduta de prompt da Sofia, fora do escopo desta frente (mas precisa entrar no handoff pro time de IA).

### Q3 — SLA de não-atendimento: tempo, consequência e destino final

- **Asked:** quanto tempo até repassar? Lead expirado conta como recebido? Pool esgotado cai pra quem?
- **Captured:**
  - Paulo: *"Lembre-se que preciso dessas nuâncias configuráveis"* → virou a **restrição permanente nº 6** do Summary (nada hardcoded; tudo em `distribuicao_policies`, por time).
  - Paulo: *"Decida você"* → **decisões tomadas pelo Claude**, registradas abaixo como **defaults de fábrica** (não constantes — editáveis por time).
- **DECIDIDO (defaults da Tozi):**

  | Campo (policy, por time) | Default | Justificativa |
  |---|---|---|
  | `sla_assumir_minutos` | **30** | O lead não está abandonado (a IA segura), então o SLA é sobre justiça, não resgate. 30 min é curto o bastante pra ser compulsório e longo o bastante pra caber um intervalo entre visitas. O log de recusa dá os dados pra calibrar depois. |
  | `sla_respeita_horario` | **true** | Relógio corre só no expediente do time; congela à noite/fim de semana. Sem isso, todo lead de sábado nasce estourado na segunda. |
  | `expirado_conta_como_recebido` | **true** | **Faz a punição virar aritmética.** Quem deixa vencer gastou a vez dele e vai pro fim da fila igual a quem atendeu → recebe menos leads sozinho, sem ninguém aplicar penalidade. Com `false`, ignorar lead é de graça. |
  | `max_repasses` | **3** | Lead é oferecido a 4 pessoas antes de escalar. Não faz sentido queimar um pool de 10 — 4 no-shows seguidos já é problema de gestão, não de distribuição. |
  | `pool_esgotado_destino` | **user_id fixo** (recepção/gestor) | Alguém precisa ser dono final; circular pra sempre é o mesmo que ninguém ser responsável. **Forma decidida** (um usuário específico, não um time). ⚠️ *Qual pessoa* = flag. |

- **Decisões correlatas (mesma pergunta, tomadas junto):**
  - **Relógio começa na designação** e pausa fora do expediente **do time** (não da conta) — times diferentes podem ter horários diferentes.
  - **Continuidade é gasta ao expirar:** se o Bruno tinha prioridade por já ter atendido o cliente e deixou vencer, o repasse vai pro **rodízio normal** — não tenta outro "continuísta". Motivo: continuidade é um benefício *pro cliente*; quem não responde não está servindo o cliente.
- **Flags:** quem é o `pool_esgotado_destino` da Tozi (recepção — Maria? Cibele #107?) → **Paulo/Guilherme**.

### Q4 — Continuidade: janela e se consome a vez no rodízio

- **Asked:** janela de 30 dias serve? Lead que vem por continuidade consome a vez do corretor no rodízio ou é "de graça"?
- **Captured:** Paulo: *"Vai"* → **confirmado tudo o que foi recomendado.**
- **DECIDIDO:**
  - `continuidade_dias` = **90** como default de **vendas** (ciclo de imóvel é longo — cliente some 2 meses e volta). Por time: **locação fica em 30** (ciclo curto; sumiu 3 meses já é lead novo). Campo já existe na policy.
  - **Continuidade CONSOME a vez no rodízio.** Motivo: senão o corretor com base grande recebe os retornos dele **mais** a fatia cheia de leads novos, e quem entrou esse mês nunca alcança. Consumindo, a carga total fica justa — quem tem muito cliente voltando recebe menos lead novo, porque o tempo dele já está ocupado.
    - Contrapartida registrada: isso pune levemente quem é bom de retenção. **Se o Guilherme quiser premiar retenção, o caminho é peso no pool (sênior 2×), não continuidade grátis.**
  - **"Já atendido" = ASSUMIU**, não "foi designado". *(Decisão técnica do Claude.)* Senão um corretor que deixou o lead vencer semana passada vira o "continuísta" dele pra sempre — o oposto do que a continuidade quer. ⚠️ **O `DistribuirService#consultor_anterior` hoje olha `assignee_id` de conversas anteriores — vai precisar passar a exigir que a conversa tenha sido de fato assumida.**
  - **Continuidade NÃO cruza time.** *(Decisão técnica do Claude — já é o comportamento do código: `where(team_id: @team.id)`.)* Comprou com o Bruno em vendas e agora quer alugar → rodízio de locação normal.
- **Flags:** nenhuma.

### Q5 — 🔴 PREMISSA CRÍTICA: os corretores vão viver dentro do SPX?

- **Asked:** o `CLAUDE.local.md` diz que *corretores NÃO usam SPX (só Vista)*. Se for verdade, "assumir" nunca acontece, a caixa "Aguardando atendimento do Bruno" nunca é aberta e a contagem mede designação, não atendimento. Três desenhos: (1) corretor entra no SPX · (2) rodízio só escreve o `CorretorNegocio` no card do Vista · (3) híbrido, Cibele assume em nome dele.
- **Captured (resposta do Paulo):**
  - **O rodízio precisa existir de qualquer jeito** — *"favorece diversos setores"*, não só corretores. Ou seja: para administrativo/locação/financeiro/recepção o desenho (1) vale integralmente.
  - **Para corretores: "tem que funcionar normalmente mesmo que eles não utilizem a plataforma"**, e *"por enquanto vai funcionar junto com o Vista"*.
  - **Causa-raiz da resistência (não é preguiça, é ferramenta):** *"os corretores atuam diferente, eles têm resistência em usar outra ferramenta que não seus próprios celulares e WhatsApp"*.
  - **A virada de chave é o app nativo do SPX** (quando ficar pronto). Até lá, convivência com o Vista.
  - Assunto já discutido em **outra sessão** (contexto existe fora daqui).
- **DECIDIDO (direção):** confirma o *"mirar no (1), entregar em cima do (3)"*. O terceiro estado, o SLA e a contagem são os mesmos — muda só **quem executa o ato de assumir**. Nada se reescreve quando o app nativo chegar.
- **CONSEQUÊNCIA DE ARQUITETURA:** "assumir" **não pode ser sinônimo de "ser o corretor"**. Tem que ser um **ato que aceita procuração** (a Cibele assume por ele) **e/ou um sinal externo**. → vira config por time: o time opera **dentro** do SPX ou **fora** dele.
- **Flags:** nenhuma (gerou a Q6).

### Q6 — Como o corretor fica sabendo que o lead é dele?

- **Asked:** proposta do Claude era **botão `Assumir` num template de WhatsApp** pro celular do corretor (usando o canal que ele aceita, e reusando a máquina do `DisparoLeadJob`). Confirmar direção + o que fazer no interino.
- **Captured — ❌ PROPOSTA CORRIGIDA PELO PAULO:**
  > *"Rodízio escolhe o Bruno → o SPX manda para o VISTA/LOFT"*
  - **A interface do corretor é o VISTA, não o WhatsApp.** Nada de template com botão pro celular dele. O SPX escreve o card no Vista com `CorretorNegocio` = o escolhido, e **o card é a notificação**.
  - Coerente com o resto: o corretor **já** cria e move o negócio no funil do Vista (STATE 23/07) — é a ferramenta dele.
- **Complemento do Paulo (mesma pergunta):**
  > *"O Rodízio no SPX será espelhado para a criação de cards no loft"*
  - **O rodízio mora no SPX** — é lá que a decisão acontece e é lá que ela é verdade. O Vista/Loft recebe o **espelho** (criação do card). Direção **SPX → Vista**.
  - Confirma o `CLAUDE.local.md`: *"Espelho no Vista (Vista = Loft, mesmo sistema): ao dar o handoff, criar o card com dossiê e corretor."*
- **CONSEQUÊNCIA:** o `VistaCardService` (receita provada em 23/07, parada só esperando a regra de rodízio) **é a saída do motor**, não um acessório. `CorretorNegocio` = output do `DistribuirService`. A máquina de estados fica **inteira no SPX**; o Vista não é fonte de verdade de nada.
- **Flags:** ver Q7 (sinal de assunção e repasse) — gerada por esta resposta.

### Q7 — A Sofia cala em vendas depois do card? + correções estruturais do Paulo

- **Asked:** (a) Sofia continua sempre · (b) modo contido (responde, não puxa assunto, não fala preço/condição) · (c) cala X horas depois do card.
- **Captured — resposta (b) + 5 correções que reescrevem o desenho:**

  **(b) MODO CONTIDO.** Sofia continua respondendo depois do card, **não puxa assunto**, e **não fala preço, condição nem disponibilidade** — nisso desvia pro corretor. **É conduta de prompt (banco conta 6) → fora do escopo desta frente.** Mas duas coisas são **requisito de código meu**, senão a conduta não tem como existir:
  1. **Carimbo do gatilho no contexto do agente** — custom attribute na conversa, mesmo caminho de `meta_campanha`/`meta_imovel`. Fonte da verdade = `Spx::Distribuicao::State`; o custom attribute é espelho de leitura pro turno.
  2. **Sinal de "pode calar" já tem dono: a `spx/eval`** vai construir o poll do Vista (card mudou de etapa = corretor engajou → Sofia silencia). **Consumir o campo, não construir outro leitor.**

  **CORREÇÃO 1 — em vendas, NÃO setar `assignee`.** Ver decisão 4-bis do Summary. Mata a proposta de "dois campos vivos" e o mexer no `reset_agent_bot_when_assignee_present`.

  **CORREÇÃO 2 — app nativo = adição, não migração.** A transição "assumir" promove designação → `assignee` e cala a IA. Designação, contagem, SLA e política ficam iguais.

  **CORREÇÃO 3 — v1 é SÓ VENDAS.** Locação e administrativo já rodam com o motor distribuindo e a IA calando. Não mexer.

  **CORREÇÃO 4 — espelho Vista atrás de flag por time** (`espelho_vista` na policy). Desligar o paliativo = configuração, não deploy.

  **CORREÇÃO 5 (confirmação) — sem repasse automático em vendas na v1.** Reescrever `CorretorNegocio` de card existente é **capacidade não testada** e o `DELETE` do Vista está **bloqueado (401)** — errar custa lead que o corretor já trabalhava. **SLA em vendas vira MEDIDA, não ação:** tela do gestor com *"12 leads designados há mais de 2h sem movimento"*. O campo `repasse_automatico` na policy está certo.

- **Contrato da escrita no Vista (a parte que É minha):**
  1. **Garantir cliente** (o Vista dedupa por telefone).
  2. **Criar o card** com `CorretorNegocio` = o designado pelo rodízio.
  3. **Gravar `vista_negocio_codigo`** na conversa.
  4. **Ser idempotente** — checar negócio ativo **antes** de criar. Com `DELETE` bloqueado, **não existe desfazer**.

- **Reconciliação com respostas anteriores:**
  - **Q3** — `sla_assumir_minutos` (30) sobrevive, mas em vendas é **limiar de alerta**, não de repasse. `max_repasses` e `pool_esgotado_destino` ficam **inertes na v1** (valem pros times com `repasse_automatico: true`). `expirado_conta_como_recebido` vira quase-moot em vendas (sem repasse, o lead não sai do designado) — mantido pro modelo geral. **A flag do `pool_esgotado_destino` deixa de bloquear a v1.**
  - **Q4** — "já atendido = assumiu" **fica sem sinal em vendas** (ninguém assume). ⚠️ Gera a Q8.
- **Flags:** ver Q8.

### Q8 — Continuidade em vendas: qual é a fonte de "quem já atendia esse cliente"?

- **Asked:** a Q4 definiu *"já atendido = assumiu"*, mas em vendas ninguém assume → continuidade nunca dispararia. Fontes: (a) a própria designação · (b) o sinal de engajamento da `spx/eval` · (c) o próprio Vista.
- **Captured:** Paulo: **"C"**.
- **DECIDIDO:**
  - **A continuidade em vendas lê o VISTA.** Ele é o sistema de registro de quem trabalha qual cliente. **Custo zero de chamada nova:** o contrato da Q7 já manda garantir o cliente (dedup por telefone) e checar negócio ativo antes de criar o card — a resposta dessa mesma chamada entrega o corretor.
  - **Degradação limpa:** Vista fora do ar, ou cliente sem negócio ativo → cai no rodízio normal.
  - **Cliente com dono FORA do pool fica com o dono.** O Vista tem ~44 corretores, o pool do rodízio tem ~4. Se o cliente já tem negócio ativo com alguém fora do rodízio, o card vai pra **esse** corretor e **o rodízio não é consumido**. Tirar cliente de quem já o atende pra dar ao "da vez" é pior que desequilibrar o rodízio.
  - **(b) entra depois como refinamento** (engajou × só tem card), quando a `spx/eval` subir — sem trocar arquitetura.
- **Flags:** nenhuma.

### Q9 — Em vendas, todo corretor atende qualquer produto?

- **Asked:** pool único sem especialização na v1 (recomendação do Claude), ou existe especialização real a modelar?
- **Captured:** ❌ **Recomendação do Claude REJEITADA pelos fatos.** Paulo mandou **print do Guilherme** com a carteira real de vendas. **A especialização é real, viva e granular.**

**Tabela do Guilherme (13 corretores, vendas) — transcrita do print:**

| Corretor | Produtos | Destaque verde |
|---|---|---|
| Alisson | TERCEIROS | |
| Bruno | SPL E LORIS | 🟩 |
| Carlos | TERCEIROS | |
| Francielli | PACAEMBU, TERCEIROS, TERRENOS / LOTEAMENTOS | 🟩 |
| Henrique | PACAEMBU E TERRENOS / LOTEAMENTOS | |
| Kettlen | SPL | 🟩 |
| Lucas | TERCEIROS | 🟩 |
| Marcos | TERCEIROS | 🟩 |
| Marcus Aurélio | SPL E TERRENOS / LOTEAMENTOS | |
| Rosivane | PACAEMBU E TUIUIU | |
| Vander | TERCEIROS | |
| Vinicius | TERCEIROS | |
| Weigler | **PACAEMBU, TERCEIROS ATÉ 600 MIL** | |
| Leandro | SPL E TERCEIROS | |

**O que a tabela ensina (requisitos que ela impõe ao modelo):**
1. **Relação é N↔N.** A maioria atende 2–3 produtos. Não é "um corretor, um produto".
2. **Produtos são um catálogo VIVO, não enum de código.** Paulo: *"os produtos que a Tozi **tem, deixa de ter ou passa a ter**"*. Vistos aqui: `TERCEIROS`, `SPL`, `LORIS`, `PACAEMBU`, `TERRENOS/LOTEAMENTOS`, `TUIUIU`. Misturam **construtora** (SPL, Pacaembú), **empreendimento** (Loris, Tuiuiú) e **categoria** (Terceiros, Terrenos/Loteamentos) — a taxonomia precisa aguentar os três sem hierarquia rígida.
3. **⚠️ Existe QUALIFICADOR por produto, não só o produto.** *"Weigler — PACAEMBU, TERCEIROS **ATÉ 600 MIL**"*: teto de valor **por produto, por corretor**. Ou seja, a associação corretor↔produto carrega **atributos** (faixa de valor), não é um par simples. É a "faixa de valor" da §3.3 do `MOTOR-DISTRIBUICAO.md`.
4. **Universo real de vendas ≈ 13 corretores** (não os ~4 que operam o SPX hoje, nem os 44 do Vista). Sub-pool por produto é viável — `TERCEIROS` tem 8 pessoas, `SPL` tem 5, `PACAEMBU` tem 4.
5. ❓ **Destaque verde não explicado** (Bruno, Francielli, Kettlen, Lucas, Marcos) → **flag**.

- **CONSEQUÊNCIA:** a decisão da Q9 vira **produto é dimensão de primeira classe do pool**. O mecanismo que o Claude tinha proposto como "se precisar" (**tag no membro do pool, não time por empreendimento**) passa a ser o caminho principal — reforçado pelo fato de que time no SPX carrega permissão + SLA + funil junto.

- **Material adicional enviado pelo Paulo:** planilha do **Léo (locação)** com o rodízio manual "modo arcaico" → `C:\Users\paulo\Downloads\Controle de Atendimento.xlsx`.
- **Flags:** significado do destaque verde na tabela do Guilherme → **Paulo/Guilherme**.

### Q9-b — Planilha do Léo (locação): como é o rodízio "arcaico"

- **Fonte:** `C:\Users\paulo\Downloads\Controle de Atendimento.xlsx` (lida em 30/07).
- **Estrutura:** **56 abas** = 28 meses × 2, de SETEMBRO/24 a DEZEMBRO/26. Cada mês tem **duas abas: `<MÊS> ONLINE` e `<MÊS> P.`** (presencial).
  - **ONLINE:** uma coluna-grupo por consultor (hoje **GELSON** e **ADRIAN**), cada uma subdividida em **4 CANAIS: `WHATSAPP · SITE · FACEBOOK · LIGAÇÃO`**. Linhas = dias do mês. Rodapé soma por canal e por consultor.
  - **PRESENCIAL:** uma coluna por consultor, contagem diária, `TOTAL DIA`, `ATENDIMENTOS/MÊS`, `MÉDIA ATENDIMENTOS/DIA`.
  - Julho/26 (parcial): online Gelson **157** × Adrian **160**; presencial Gelson **25** × Adrian **34**. Métricas derivadas: `TOTAL ATENDIMENTOS`, `MÉDIA ATENDIMENTO/WHATSAPP`, `MÉDIA SITE`, `MÉDIA ATENDIMENTO/LIGAÇÃO`.

- ~~**DESCOBERTA — a planilha é um PLACAR, logo o rodízio arcaico é equalização por contagem** (≠ ponteiro sequencial do `DistribuirService`).~~ **🚫 LEITURA ERRADA — corrigida pelo Paulo:**
  > *"Não, você entendeu errado. É só o que precisa haver de controle. Quero uma tela onde possa ser visto como está sendo contabilizado o rodízio. Com base nas regras e tudo mais. **Mas como funciona o rodízio é exatamente como estávamos construindo**."*
- **✅ O QUE A PLANILHA REALMENTE É: o requisito de uma TELA DE CONTROLE.** Ela mostra o **nível de visibilidade** que a gestão espera ter da contabilização — não o algoritmo. **O algoritmo permanece o que já está desenhado e implementado** (rodízio por ponteiro no `DistribuirService`). **A Q10(a) — trocar ponteiro por contagem — está REVOGADA; nada muda no motor.**
- **Entregável derivado:** **tela de contabilização do rodízio**, mostrando como está sendo contado *com base nas regras aplicadas*. Matéria-prima já existe: **`distribuicao_logs`** (conversa, escolhido, `motivo` continuidade|rodizio|sem_pool, candidatos, timestamp). Some-se a isso o SLA-como-medida decidido na Q7 (*"12 leads designados há mais de 2h sem movimento"*).

- **O que a planilha define como REQUISITO DA TELA** (não do algoritmo):
  1. **Recorte por CANAL** (WhatsApp · Site · Facebook · Ligação). O SPX sabe isso (inbox/source) — falta expor.
  2. **Recorte MENSAL** — uma aba por mês, fecha e zera na virada. A tela precisa de período, com o mês como padrão.
  3. **Totais e médias por consultor** — `TOTAL DE ATENDIMENTO` por canal e consolidado, `MÉDIA/DIA`, `MÉDIA por canal`.
  4. **PRESENCIAL é uma coluna paralela** que o SPX não origina (balcão). A tela reproduz o que o SPX distribui; a carga de balcão fica fora — **limitação conhecida, registrada, não é pergunta** (o algoritmo por ponteiro não depende dela).
  5. Escala real: locação = **2 consultores**, ~**1.000 atendimentos online/mês** (jun/26: Gelson 510 × Adrian 536) + 201 presenciais. Vendas = **13 corretores**. A tela tem que aguentar esse volume.

### Q11 — Modelo de produtos: como o catálogo é identificado e cruzado

- **Asked:** confirmar o modelo (catálogo com matchers + vínculo corretor↔produto com qualificador de valor).
- **Captured (direção do Paulo, pensando em voz alta):**
  > *"Catálogo tem que ser identificado e cruzado com **intenção do cliente**, **entrada por lead com dados de campanha**, etc... Deve ter **opções inclusive na hora de criar o card no Vista**. Eu acho. Mas vamos pensar em algo."*
  - Não é só "corretor↔produto". O produto tem que ser **resolvido a partir de vários sinais** e depois **usado em vários lugares** — inclusive na criação do card.
- **PROPOSTA (Claude) — o produto vira a JUNÇÃO do fluxo inteiro:**

  **Entrada (campanha) → Intenção (Sofia) → Pool (corretor) → Card (Vista) → Tela (contabilização)**

  **(1) Sinais de identificação, com precedência** — resolvidos **no momento do handoff** (quando a Sofia já qualificou):
  | # | Sinal | Fonte | Já existe? |
  |---|---|---|---|
  | 1 | **Intenção declarada** na conversa | Sofia (`salvar_info_lead`, `registrar_observacao`) | ✅ tools existem |
  | 2 | **Imóvel do anúncio** → categoria/empreendimento/**valor** | `meta_imovel_codigo` → Vista | ✅ carimbado (defs 80/81) |
  | 3 | **Campanha/anúncio de entrada** | `meta_campanha` + override `empreendimento`/`lead_tipo` | ✅ carimbado (defs 75-79) |
  | 4 | nada | — | → **pool inteiro do time** |

  **Intenção ganha da campanha** — o lead clicou no anúncio do Etna mas diz que quer terreno; quem atende tem que ser o de terreno. O timing funciona porque a designação acontece **depois** da qualificação.

  **(2) Registro de produto (catálogo, por conta):**
  ```
  slug: 'spl' · nome: 'SPL' · ativo: true
  matchers:  empreendimentos: [...nomes/códigos Vista...]
             categorias: [...]        # categoria do Vista
             campanhas:  [...campaign_id Meta...]
             palavras:   [...]        # intenção
  vista:     pipe, etapa, veiculo_captacao, prefixo_nome_negocio
  ```
  O bloco `vista:` atende o *"opções na hora de criar o card"* — **o produto carrega os defaults do card**, em vez de hardcodar `Pipe 3 / PROSPECTO / "C - <imóvel>"` no serviço.

  **(3) Vínculo no pool com qualificador** (o caso Weigler):
  ```
  { user_id: <Weigler>, produtos: [ {produto:'pacaembu'}, {produto:'terceiros', valor_max: 600000} ] }
  ```
  **Valor de referência do lead** vem do imóvel (Vista) ou do que a Sofia capturou. **Decisão pendente:** valor **desconhecido** → o teto **não filtra** (mantém elegível). Excluir alguém por dado ausente é pior que incluir; o corretor redireciona internamente. ⚠️ risco aceito: lead de 900k pode cair no Weigler quando o valor não foi capturado.

  **(4) Bônus:** produto vira **dimensão da tela** de contabilização (recebidos por produto), sem trabalho extra.

- **Flag do verde — RESOLVIDA (descartada):** Paulo: *"Eu não sei o que é esse verde. Provável que seja quem estava participando dos disparos da base de leads e estava usando SPX para atender. Mas melhor **ignorar**."*
  - ✅ **Não é dimensão do modelo.** Não modelar.
  - 📌 Anotado como pista lateral (não usar como regra): os 5 verdes (Bruno, Francielli, Kettlen, Lucas, **Marcos**) batem quase 1:1 com os corretores que operam o SPX segundo o `STATE.md` (Kettlen #126, Lucas #127, Marcus #128, Bruno #131). Serve como **chute inicial do pool de vendas na v1** (~5 dos 13), a ser confirmado com o Guilherme na hora de configurar — não como regra de código.
- **DECIDIDO (precedência — sem objeção do Paulo, decisão do Claude):** **intenção > imóvel do anúncio > campanha de entrada > nada**. Caso que manda: lead clica no anúncio do Etna (→ Kettlen, SPL) mas na conversa diz que quer terreno (→ Marcus Aurélio / Francielli). O segundo é o certo, e é o *"podem migrar de interesse"* já registrado no `STATE.md`.

### Q12 — Fechamento: exceção do consultor pedido, punição, comissionamento + backstop

- **Captured (respostas do Paulo):**
  1. **Cliente pede consultor específico → SIM**, como recomendado: honra o pedido (mesmo fora do pool), **consome a vez**, e grava com **motivo próprio `preferencia_cliente`** — separado de `continuidade` e `rodizio`.
     - Razão de existir o motivo separado: é a **única porta de bypass do rodízio** ("pede por mim" reabre o cherry-pick que o Guilherme quer matar). Não dá pra bloquear sem irritar cliente real; dá pra **deixar visível na tela**. Punir é decisão humana; o código só não pode esconder.
  2. **Punição = MANUAL.** `ativo: false` no pool. Nada automático na v1 (sem repasse em vendas, não há sinal automático de recusa em que basear). Punição automática só depois do sinal de engajamento da `spx/eval`.
  3. **Comissionamento: "veremos depois".** Limite registrado: na v1 o SPX sabe contar **lead recebido**, não **lead atendido** (ninguém assume no SPX em vendas). Comissionar por atendimento real depende do sinal do Vista da `spx/eval`.

- **Backstop — 4 requisitos NOVOS levantados pelo Paulo:**
  | # | Requisito | Tratamento |
  |---|---|---|
  | a | **Férias** | Pool precisa de disponibilidade. v1: `ativo: false` (pausa manual) já cobre. |
  | b | **Escala** (turnos/dias) | Dimensão nova do pool. **Fora da v1** → próxima onda (F2 do `MOTOR-DISTRIBUICAO.md`). |
  | c | **Quem está online no SPX** — *"exceto vendas por ora"* | É o `so_online`, coluna que **já existe e está parqueada**. Aplica-se aos times que **vivem** no SPX (locação/administrativo), **não a vendas** (corretor não está lá). ⚠️ Tensão a respeitar: esses times *"já rodam hoje — não mexa no que funciona"* (decisão 9) → entra como onda seguinte, com cuidado. |
  | d | **Gestor altera atribuição por cima do rodízio** | **Sempre permitido.** Decisões do Claude: (1) grava no log com `motivo: 'manual_gestor'` — senão a tela mente; (2) **conta como recebido** pro corretor (é lead de verdade, e a visibilidade é o freio contra o gestor viciar a distribuição); (3) **não move o ponteiro** do rodízio (não faz parte da sequência). |

- **Lead de madrugada:** *"eu acho normal, IA atende, faz handoff, continua conversando se for o caso."* → **Nenhum tratamento especial.** Já coberto por "designa na hora" (Q2) + "SLA respeita horário do time" (Q3) + "modo contido" (Q7).

- **Autorização dada:** *"Faça o que for preciso garantindo que nada seja perdido"* → sincronizar a base e escrever a spec.

---

## Open flags (pending input)

- Redação/gatilho do anúncio "um consultor vai entrar em contato" → **prompt da Sofia (conta 6)**, não código desta frente.
- Conduta "modo contido" (não falar preço/condição/disponibilidade após o card) → **prompt da Sofia (conta 6)**, fora do escopo. Depende do carimbo (requisito 1) estar no ar.
- Nome/formato do campo que a **`spx/eval`** vai expor pro sinal "corretor engajou" → **alinhar com a frente `spx/eval`** antes de codar o consumo.
- Usuário destino do `pool_esgotado_destino` na Tozi → **Paulo/Guilherme** (⏸️ não bloqueia a v1: sem repasse em vendas).
- Composição inicial do pool de vendas (pista: os 5 destacados ≈ quem usa o SPX) → **Guilherme**, na hora de configurar.

---

## Encerramento

- **Sessão fechada em 30/07/2026.** Backstop aplicado: Paulo levantou 4 requisitos novos (férias, escala, online, override do gestor) — todos tratados na Q12. Lead de madrugada: sem tratamento especial.
- **Base sincronizada:** `git merge --ff-only origin/homologacao` executado → `6ef8340e5` → **`a75b08c54`** (45 commits). O `Spx::TemplateReplyRouterListener` chegou junto e foi lido: confirma que cobre 2 das 3 exceções, e que o RMKT **volta pra IA** (logo entra no rodízio depois de requalificar).
- **Entregável desta sessão:** **[`docs/clientes/tozi/SPEC-RODIZIO.md`](../docs/clientes/tozi/SPEC-RODIZIO.md)** — versão organizada deste brainstorm, pronta pra implementação.
- **Este arquivo continua sendo o registro bruto** (perguntas, respostas verbatim, e as recomendações do Claude que foram **rejeitadas** — Q7 correção 1, Q9, Q10a). A spec não repete a rastreabilidade; ela mora aqui.
