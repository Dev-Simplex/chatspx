---
titulo: Spec — Rodízio, Designação e Espelho no Vista
cliente: Tozi Imóveis (conta 6) — mecanismo genérico, configurável por conta/time
frente: spx/rodizio
status: SPEC (fechada com o Paulo em 30/07/2026) — pronta para implementação
data: 2026-07-30
base: a75b08c54 (origin/homologacao)
brainstorm: brainstorms/2026-07-30-rodizio-atribuicao-tozi.md
ai-generated: true
tags: [spx, rodizio, distribuicao, designacao, vista, captain]
---

# Spec — Rodízio, Designação e Espelho no Vista

> **Como ler:** o §1 é o que já existe (não reimplementar). O §2 são as âncoras que não
> se negociam sem refazer a spec. Do §3 em diante é o que construir.
> Rastreabilidade completa (perguntas, respostas e recomendações rejeitadas) no brainstorm.

---

## 1. Ponto de partida — o que JÁ EXISTE

O motor F1 de distribuição **está implementado e ligado**. Esta frente **não** o reescreve.

| Peça | Onde | Estado |
|---|---|---|
| `Spx::Distribuicao::DistribuirService` | `app/services/spx/distribuicao/distribuir_service.rb` | ✅ continuidade → rodízio (ponteiro) → `sem_pool`, com cap e log |
| `Policy` / `State` / `Log` | `app/models/spx/distribuicao/` + migration `20260701150000` | ✅ migrados |
| Gancho no handoff | `Captain::Conversation::HumanHandoffService#perform` | ✅ chama o `DistribuirService` |
| `resolve_team` | idem | ✅ ligado |
| `Spx::TemplateReplyRouterListener` | `app/listeners/spx/template_reply_router_listener.rb` | ✅ opt-in por conta |
| `so_online` | coluna em `distribuicao_policies` | ⚠️ existe, **serviço ignora** |
| `modo: 'online'` | aceito pelo `Policy` | ⚠️ não implementado (no-op) |

**Origem:** `docs/clientes/tozi/MOTOR-DISTRIBUICAO.md` (kickoff 01/07, pedido do Guilherme).

---

## 2. Âncoras (decisões que sustentam todo o resto)

1. **A IA é extensão do atendimento, não etapa.** O handoff é **evento de sistema, silencioso**.
   A IA **nunca** anuncia ("vou chamar um consultor", "segunda-feira alguém te procura").
   O anúncio, quando faz sentido, é decisão conversacional dela — desacoplada do handoff,
   podendo ocorrer horas ou dias depois.
2. **Designado ≠ assumido.** São estados distintos. A designação é **estado de primeira classe**.
3. **Em vendas NÃO se seta `assignee`.** `assignee` significa *"humano dono dentro do SPX"* — em
   vendas isso é falso hoje. Forçar o campo é mentir no dado.
4. **Zero mudança no `reset_agent_bot_when_assignee_present`** (`app/models/conversation.rb:370`).
   Como `assignee` fica nulo, o callback não dispara, o espelho captain sobrevive e **a IA
   continua atendendo sem uma linha de alteração no core.**
5. **Nada de `custom_attribute` como fonte da verdade.** Ele é espelho de leitura para o turno do agente.
6. **Nenhum número mágico em código.** Toda nuância é configurável **por time**, na `distribuicao_policies`.
   Os valores deste documento são **defaults de fábrica da Tozi**.
7. **O algoritmo do rodízio não muda** — segue por ponteiro, como já implementado.
8. **App nativo = adição, não migração.** Quando os corretores entrarem no app, a única novidade é a
   transição *assumir* (promove designação → `assignee` e cala a IA). Designação, contagem, SLA e
   política permanecem idênticos.
9. **Escopo da v1 = SÓ VENDAS.** Locação e administrativo já rodam com o motor distribuindo e a IA
   calando — **não mexer no que funciona.**

---

## 3. Máquina de estados da conversa

```
                     ┌──────────────────────────────────────────┐
                     │  IA ATENDENDO                            │
                     │  assignee=nil · espelho captain=vivo     │
                     └───────────────┬──────────────────────────┘
                                     │ handoff (silencioso)
                                     │ → resolve produto → filtra pool → escolhe corretor
                                     ▼
   ┌───────────────────────────────────────────────────────────────────────┐
   │  DESIGNADO                          (estado NOVO — o núcleo da frente) │
   │  assignee = nil          ← não muda                                    │
   │  espelho captain = VIVO  ← IA continua atendendo, em MODO CONTIDO      │
   │  designação  = registro em distribuicao_logs (corretor, quando, regra) │
   │  espelho     = card criado no Vista com CorretorNegocio                │
   │  carimbo     = custom attributes na conversa (contexto do agente)      │
   └───────┬───────────────────────────────────┬───────────────────────────┘
           │ humano assume no painel           │ corretor engaja no Vista
           │ (Cibele por procuração, ou o      │ (card muda de etapa —
           │  próprio, no app nativo)          │  sinal produzido pela spx/eval)
           ▼                                   ▼
   ┌────────────────────────┐        ┌──────────────────────────────┐
   │  ASSUMIDO              │        │  ENGAJADO (fora do SPX)      │
   │  assignee = humano     │        │  assignee segue nil          │
   │  espelho captain = nil │        │  IA silencia                 │
   │  IA calada (callback   │        │  designação → status engajado│
   │  nativo, sem mudança)  │        └──────────────────────────────┘
   └────────────────────────┘
```

**Modo contido** (estado DESIGNADO): a IA responde, **não puxa assunto**, e **não fala preço,
condição nem disponibilidade** — nisso desvia para o corretor.
👉 É **conduta de prompt** (banco da conta 6, via Almirante `ai_update_prompt`), **fora do escopo
desta frente**. Esta spec entrega apenas os dois requisitos que a tornam possível: o **carimbo**
(§6) e o consumo do **sinal de engajamento** (§8.3).

### 3.1. Times que vivem dentro do SPX

Para locação/administrativo/financeiro/recepção o fluxo é o **atual** (designar = atribuir
`assignee`, IA cala). Nada muda na v1. A diferença é uma chave na policy (§5.1, `modo_posse`).

---

## 4. Resolução do produto

O produto é o eixo que costura entrada → intenção → pool → card → tela. É resolvido **no momento
do handoff** (a Sofia já qualificou), pela **primeira** fonte que responder:

| # | Sinal | Fonte | Disponível hoje |
|---|---|---|---|
| 1 | **Intenção declarada** | Sofia (`salvar_info_lead`, `registrar_observacao`) | tools no ar |
| 2 | **Imóvel do anúncio** → categoria, empreendimento e **valor** | `meta_imovel_codigo` → Vista | carimbado (defs 80/81) |
| 3 | **Campanha de entrada** | `meta_campanha` + override `empreendimento` / `lead_tipo` | carimbado (defs 75-79) |
| 4 | nada | — | → **pool inteiro do time** |

**Intenção ganha da campanha.** Caso que manda a regra: o lead clica no anúncio do Etna (produto
SPL) mas na conversa diz que quer terreno. Pela campanha iria para um corretor de SPL; pela
intenção vai para um de terrenos — e o segundo está certo. É o *"podem migrar de interesse"* já
registrado no `STATE.md`.

---

## 5. Modelo de dados

### 5.1. `distribuicao_policies` — campos NOVOS

| Campo | Tipo | Default Tozi | Função |
|---|---|---|---|
| `modo_posse` | string | `designacao` (vendas) · `assignee` (demais) | `assignee` = comportamento atual (atribui e a IA cala). `designacao` = registra a designação e **não** toca em `assignee` |
| `espelho_vista` | bool | `true` (vendas) | Cria o card no Vista. **Nunca hardcoded** — desligar o paliativo é configuração, não deploy |
| `repasse_automatico` | bool | `false` (vendas) | Sem repasse em vendas na v1 (ver §7.2) |
| `sla_assumir_minutos` | int | `30` | Minutos de **horário comercial** até estourar |
| `sla_respeita_horario` | bool | `true` | Relógio congela fora do expediente **do time** |
| `expirado_conta_como_recebido` | bool | `true` | Quem deixa vencer gastou a vez → punição vira aritmética |
| `max_repasses` | int | `3` | Voltas antes de cair no destino final |
| `pool_esgotado_destino_user_id` | bigint | ⚠️ flag | Dono final quando ninguém assume |
| `igualdade_janela` | string | `mes` | Janela de contagem da tela |
| `continuidade_dias` | int | `90` (vendas) · `30` (locação) | Já existe; muda o default |

### 5.2. `distribuicao_produtos` — catálogo NOVO (por conta)

```
account_id · slug · nome · ativo:bool

matchers:jsonb    empreendimentos: []   # nomes/códigos do Vista
                  categorias:      []   # categoria do Vista
                  campanhas:       []   # campaign_id da Meta
                  palavras:        []   # intenção

vista:jsonb       pipe · etapa · veiculo_captacao · prefixo_nome_negocio
```

- **Catálogo vivo:** produto novo é uma linha; produto que a Tozi deixou de vender é
  `ativo: false` — some do rodízio e para de gerar card, **sem tocar em código**.
- **Taxonomia plana, não hierárquica.** A carteira real mistura construtora (SPL, Pacaembú),
  empreendimento (Loris, Tuiuiú) e categoria (Terceiros, Terrenos/Loteamentos). Hierarquia rígida
  quebra na primeira exceção.
- 🚧 **GUARD DE ESCOPO (Paulo, 30/07): NÃO inventar taxonomia.** O **Vista já tem** empreendimento e
  tipo — o catálogo **reaproveita** o que existe lá; os `matchers` só amarram o que o Vista não
  cobre (campanha, intenção). **Se o catálogo crescer, ele é a PRIMEIRA coisa a cortar do escopo.**
- **O bloco `vista:` paga uma dívida:** sem ele, `Pipe 3 / PROSPECTO / "C - <imóvel>"` sairia
  hardcodado no `VistaCardService`.

### 5.3. `pool` (jsonb da policy) — entrada estendida

```
{ user_id, ativo, cap,
  produtos: [ { produto: <slug>, valor_max: <int|null> } ] }
```

O qualificador `valor_max` existe porque a carteira real exige: há corretor que atende um produto
**apenas até certo valor**. A associação corretor↔produto carrega atributos; não é par simples.

### 5.4. `distribuicao_logs` — o livro-razão da designação

É aqui que a designação vive (âncora 2). Campos **novos**:

| Campo | Função |
|---|---|
| `status` | `designado` · `assumido` · `engajado` · `expirado` · `substituido` |
| `designado_em` / `encerrado_em` | Relógio do SLA e base da tela |
| `produto_slug` | Produto resolvido (§4) |
| `policy_snapshot`:jsonb | **Regra que valeu na hora**: pool elegível, filtro que cortou quem, valores da policy |
| `vista_negocio_codigo` | Código do card espelhado |

⚠️ **`policy_snapshot` é requisito, não luxo.** A tela precisa explicar *"por que este lead foi
para o Bruno"*. Se amanhã o Guilherme tirar alguém do pool, os registros de ontem têm que
continuar explicando a decisão de ontem. Barato agora, caro depois.

**`motivo`** (campo já existente) ganha valores novos: `continuidade` · `rodizio` · `sem_pool` ·
`preferencia_cliente` · `manual_gestor`.

---

## 6. Carimbo de contexto (requisito para o modo contido existir)

A designação é carimbada na conversa como **custom attribute**, pelo mesmo caminho por onde já
entram `meta_campanha` e `meta_imovel` (`CustomAttributeDefinition` + serviço de stamp).

- Campos: corretor designado · quando · produto resolvido.
- **Fonte da verdade continua sendo `distribuicao_logs`.** O custom attribute é **espelho de
  leitura para o turno do agente** — sem ele, o gatilho não fica visível para o LLM e a conduta
  "modo contido" não tem como existir.

---

## 7. Algoritmo — ordem de decisão

Nenhuma mudança no rodízio em si (âncora 7). O que muda é o que acontece **antes** e **depois**.

### 7.1. Designação (no handoff)

```
1. resolve produto                       (§4)
2. pool = membros do time ∩ pool ativo   (já existe)
       ∩ atende o produto                (NOVO)
       ∩ dentro do valor_max             (NOVO)
       ∩ abaixo do cap                   (já existe)
3. preferência do cliente?  → esse corretor        motivo=preferencia_cliente   ⚠️ ver §10
4. continuidade?            → consultor anterior   motivo=continuidade
5. senão                    → próximo do ponteiro  motivo=rodizio
6. pool vazio               → não designa          motivo=sem_pool
7. registra log + carimba conversa + (se espelho_vista) cria card no Vista
```

**Continuidade em vendas lê o VISTA** — ele é o sistema de registro de quem trabalha qual cliente,
e a chamada já acontece nesse ponto do fluxo (§8.1 manda garantir o cliente e checar negócio
ativo). Custo zero de chamada nova. Vista indisponível ou sem negócio ativo → cai no rodízio.

- **Cliente com dono FORA do pool fica com o dono.** O Vista tem ~44 corretores; o pool tem poucos.
  Tirar cliente de quem já o atende para dar ao "da vez" é pior que desequilibrar o rodízio.
  Nesse caso **o rodízio não é consumido**.
- **Valor desconhecido não filtra.** Excluir alguém do rodízio por um dado que a Sofia não capturou
  é injustiça silenciosa e ninguém descobre. Risco aceito: um lead acima do teto pode cair em quem
  tem limite — e aí ele repassa internamente, como já acontece hoje.

### 7.2. SLA

| | Times no SPX (`repasse_automatico: true`) | **Vendas** (`false`) |
|---|---|---|
| Estourou | **repassa** ao próximo, marca `expirado` | **não repassa** — vira **medida** |
| Consequência | conta como recebido → punição aritmética | aparece na tela: *"N leads designados há mais de X sem movimento"* |
| Esgotou o pool | cai em `pool_esgotado_destino_user_id` | n/a |

**Relógio:** ver **§8.4**. `t0` = timestamp da designação (nosso, exato); parada = `vista_engajado_em`
(±intervalo do poll). **Nunca** usar data do Vista para contar tempo contra corretor.

**Por que sem repasse em vendas:** o card no Vista já existe com o nome do corretor. Repassar
exigiria reescrever o `CorretorNegocio` de um card existente — **capacidade não testada**, e o
`DELETE` do Vista está **bloqueado (401)**. Errar custa um lead que o corretor já trabalhava.

**Continuidade é gasta ao expirar:** quem tinha prioridade e deixou vencer devolve o lead ao
rodízio normal. Continuidade é benefício **do cliente**; quem não responde não está servindo o cliente.

### 7.3. Override do gestor

Sempre permitido. Três regras:
1. Grava log com `motivo: 'manual_gestor'` — senão a tela mente.
2. **Conta como recebido** para o corretor (é lead de verdade; a visibilidade é o freio contra o
   gestor viciar a distribuição).
3. **Não move o ponteiro** do rodízio — não faz parte da sequência.

---

## 8. Espelho no Vista (Vista = Loft)

**Direção única: SPX → Vista.** O rodízio mora no SPX; é lá que a decisão é verdade. O Vista
recebe o espelho. A máquina de estados **não** depende do Vista.

### 8.1. Contrato de escrita (receita provada em 23/07 — ver `STATE.md`)

1. **Garantir o cliente** — o Vista dedupa por telefone.
2. **Criar o card** com `CorretorNegocio` = o designado pelo rodízio; pipe/etapa/nome vindos do
   bloco `vista:` do produto (§5.2).
3. **Gravar `vista_negocio_codigo`** na conversa e no log.
4. **Ser idempotente** — checar negócio ativo **antes** de criar. Com `DELETE` bloqueado (401),
   **não existe desfazer**.

Tudo isso atrás de `espelho_vista` (§5.1).

### 8.2. Limpeza pendente
Registros do teste de 23/07 a remover manualmente: cliente **65205**, negócios **85015/85016/85017**.

### 8.3. Contrato de campos com a `spx/eval` — **DECIDIDO, não alinhar**

A **`spx/eval`** constrói o poll do Vista. Esta frente **consome os campos**; **não construir
outro leitor**.

| Campo | Quem escreve | Significado |
|---|---|---|
| `vista_negocio_codigo` | **esta frente**, na criação | id do card |
| `vista_etapa` | `spx/eval` (poll) | etapa atual observada |
| `vista_engajado_em` | `spx/eval` (poll) | **timestamp da 1ª mudança de etapa observada DEPOIS da designação** |
| `vista_corretor` | `spx/eval` (poll) | corretor atual no card — detecta troca por fora |
| `vista_sync_em` | `spx/eval` (poll) | última varredura |

**`vista_engajado_em` é o sinal de "o corretor pegou".** `nil` = ninguém mexeu. É o que dispara
o silêncio da Sofia **e** o que para o cronômetro do SLA.

### 8.4. O relógio do SLA é NOSSO — não depende do Vista

- **t0 = timestamp da designação** no `Spx::Distribuicao::State`. **Exato.**
- **Parada = `vista_engajado_em`**, com erro **limitado pelo intervalo do poll (±intervalo)**, em
  vez de fingir exatidão.
- 🚫 **Nunca contar tempo contra corretor usando data do Vista.** Com isso o bug do
  `/negocios/atividades` deixa de importar para esta frente.
- **Ganho político:** o número que o gestor mostra é medido pelo SPX, com margem declarada — não
  é contestável como "o dado do Vista está errado".

### 8.5. Contrato observado hoje na conta 6 (dispensa probe)

- `/negocios/detalhes` — exige o parâmetro de **código do negócio**.
- `/negocios/listar` — exige **`codigo_pipe` ou `codigo_cliente`**; `codigo_cliente` é justamente a
  busca usada na checagem de negócio ativo (§8.1 item 4).
- **Não há catálogo de campos** — a descoberta é **empírica**.
- `listar` precisa do filtro **explícito em `pesquisa`**.
- ⚠️ **O contrato final só fecha contra um card criado pela própria frente.**

---

## 9. Tela de contabilização

Requisito trazido pela planilha do Léo (`Controle de Atendimento.xlsx`) — que é **placar de
controle, não descrição do algoritmo**. Escala real: locação = 2 consultores e ~1.000 atendimentos
online/mês; vendas = 13 corretores.

**Linha por corretor · período com mês por padrão:**

- **Recebidos** no período — o número que a gestão quer ver igual entre todos.
- **Quebra por motivo** — rodízio × continuidade × preferência do cliente × manual do gestor.
  *Sem isso o número "igual" mente*: quem tem carteira grande recebe mais por continuidade e
  parece privilegiado.
- **Recorte por canal** — WhatsApp · Site · Facebook · Ligação (derivável de inbox/source).
- **Sem movimento há mais de X** — o SLA-como-medida (§7.2).
- **Recorte por produto** — sai de graça do §5.2.
- **Drill-down por lead** — *por que este foi para o Bruno*: motivo, candidatos, e a política que
  valia na hora (`policy_snapshot`).

**Fora do alcance, registrado:** atendimento **presencial** (balcão) não passa pelo SPX e não
aparece na tela. O algoritmo por ponteiro não depende dele.

---

## 10. Exceções — o que NÃO entra no rodízio

| Situação | Comportamento | Onde vive |
|---|---|---|
| **Template manual 1:1** | Fica com quem enviou o template | ✅ `Spx::TemplateReplyRouterListener` (já existe) |
| **Disparo/RMKT** | Volta para a IA, que decide se o cliente mudou de assunto → **depois** entra no rodízio | ✅ mesmo listener |
| **Cliente pede um consultor** | **Conduta da IA** — ela aciona o handoff e o lead entra no rodízio. **Não é lacuna e não é código desta frente.** | ✅ conduta (conta 6) |
| **Continuidade** | Cliente volta para quem já o atende | ✅ existe (adaptar a fonte para o Vista) |
| **Override do gestor** | Sempre permitido, sempre logado | 🔨 construir |

⚠️ **A preferência do cliente é a única porta de bypass do rodízio.** Basta um corretor dizer ao
cliente *"pede por mim"* e o cherry-pick que o Guilherme quer matar volta pela janela. Não dá para
bloquear sem irritar cliente de verdade — **dá para deixar visível**: quem aparece com muito lead
por preferência está fazendo alguma coisa. Punir é decisão humana; o código só não pode esconder.

---

## 11. Fora da v1 (próximas ondas)

| Item | Por quê |
|---|---|
| **Escala/turnos** no pool | Dimensão nova; F2 do `MOTOR-DISTRIBUICAO.md` |
| **`so_online`** | Coluna existe, parqueada. Vale para times que **vivem** no SPX — **não vendas**. Mexe em quem "já funciona" → onda própria, com cuidado |
| **Punição automática** | Sem repasse em vendas, não há sinal automático de recusa. Depende do engajamento da `spx/eval` |
| **Comissionamento** | "Veremos depois". Limite honesto: a v1 sabe contar **lead recebido**, não **lead atendido** |
| **Promoção designação → `assignee`** | Chega com o **app nativo**. É adição, não migração |
| **"Aguardando atendimento" como caixa pessoal** | Depende de `assignee` setado; volta com o app nativo |

**Férias** entram na v1 pela porta simples: `ativo: false` no pool (pausa manual) — que é também a
**punição manual** decidida.

---

## 12. Riscos e limitações conhecidas

1. **Duas vozes.** O corretor liga do celular dele enquanto a IA segue ativa no número da Tozi.
   Mitigado — não eliminado — pelo modo contido (não fala preço/condição/disponibilidade) e pelo
   sinal de engajamento da `spx/eval`.
2. **Carga presencial invisível** (§9).
3. **Card no Vista sem desfazer** — `DELETE` 401. Daí a idempotência obrigatória (§8.1).
4. **Valor desconhecido não filtra** (§7.1) — risco aceito conscientemente.
5. **Preferência do cliente é bypass explorável** (§10) — mitigado por visibilidade.

---

## 13. Flags pendentes

| Item | Dono | Bloqueia? |
|---|---|---|
| Usuário do `pool_esgotado_destino` na Tozi | Guilherme (na configuração) | não |
| Composição inicial do pool de vendas | Guilherme (na configuração) | não |
| Conduta "modo contido" no prompt da Sofia | banco da conta 6 (fora desta frente) | não |
| Gatilho do anúncio *"um consultor vai entrar em contato"* | banco da conta 6 (fora desta frente) | não |
| **§7.1 passo 3 sobrevive?** Se "cliente pede consultor" é conduta da IA que cai no rodízio normal (§10), o desvio por `preferencia_cliente` **deixa de existir** — ou a IA registra a preferência e a designação a honra? | **Paulo** | **sim**, no passo 1 da implementação |

✅ **Resolvido em 30/07:** contrato de campos com a `spx/eval` (§8.3) — **decidido, não alinhar.**
