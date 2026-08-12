---
titulo: Por que a cutucada some depois do handoff — conversas 22804 e 22798
frente: spx/followup
tipo: investigação read-only (não implementa)
ambiente: Tozi PRODUÇÃO · conta 6 · 3.82.215.109
data: 2026-08-11
---

# A cutucada não morre no handoff. Ela nunca chega a nascer.

> **Investigação read-only.** Nada foi escrito, migrado, reiniciado ou deployado. Toda afirmação
> aqui sai de `Captain::AssistantLog`, `captain_tool_calls`, `messages` e `custom_attributes` lidos
> na produção da Tozi em 11/08/2026 23:34 UTC. Os scripts estão no fim do documento.

## Resumo em cinco linhas

1. **Nenhuma das duas conversas morreu por `owner_assistant` nil nem por `followup_pointless?`.**
   As duas morreram um passo antes: o `auto_schedule_followup` **nunca armou o token**, porque
   `ja_tem_destino?` vê `aguardando_humano_desde` e sai — e quem escreveu esse marcador foi o
   handoff, no mesmo turno, segundos antes.
2. **O espelho não caiu no handoff.** Ele sobreviveu 18h42 (22804) e 20h02 (22798), e só caiu
   quando a Cibele se atribuiu a conversa na manhã seguinte.
3. **A frase "a IA emudece exatamente quando o rodízio funciona" está DESMENTIDA nestes dois
   casos** — e por um motivo mais desconfortável: o rodízio não rodou. Não existe uma única
   `Spx::Distribuicao::Policy` na conta 6 (0 políticas, 0 `distribuicao_logs`). A IA emudeceu com o
   rodízio inerte e com o espelho na mão. **A frase certa é: a IA emudece quando promete um
   humano.** O rodízio é uma agravante futura, não a causa presente.
4. **Não havia compromisso (`followup_motivo`) armado em nenhuma das duas** — zero chamadas de
   `programar_followup`. Logo **não é** a "aresta aceita" descrita no handoff da frente. É um caso
   distinto e, ao contrário daquele, **não é auto-curável pela tool** (§5).
5. **Espera real sem ninguém: 18,7 h e 20,0 h de relógio de parede — mas ~4h40 e ~4h30 de horário
   comercial.** Essa diferença é a proposta inteira: um teto em relógio de parede dispara de
   madrugada; o teto tem que correr no relógio comercial do agente.

---

## 1. As duas conversas, com hora

Fuso do dump: UTC. Entre parênteses, hora local de Sinop (America/Cuiaba, UTC−4).

### 22804 — Bianca · chácara cód 4000 · R$ 2.100.000

| Hora (UTC) | O que aconteceu | Evidência |
|---|---|---|
| 10/08 18:01:34 | conversa criada, espelho da Júlia (#13) atribuído | `mirror_assigned` |
| 10/08 18:03:16→18:04:01 | IA manda fotos, descreve o imóvel e **pergunta**: "Você está procurando pra morar ou é investimento?" | `debounce_fire`, `humanizer_split sent=3` |
| 10/08 18:09:17 | cliente responde "investimento" | msg 1619157 |
| 10/08 18:09:39 | novo turno da IA começa → `reset_followup_state` zera o token da cutucada anterior | `debounce_fire` |
| **10/08 18:09:46** | **handoff pela tool do agente** — dossiê privado + `aguardando_humano_desde` + time `vendas` (#26) | `AssistantLog handoff {"team_id"=>26,"com_dossie"=>true}` + `ToolCall handoff status=ok` |
| 10/08 18:09:57→18:10:07 | IA continua atendendo e **deixa outra pergunta no ar**: "Como você pretende investir, à vista ou com financiamento?" | msgs 1619166/1619169 |
| — | **silêncio de 18h42. Nenhuma cutucada. Nenhum humano.** | — |
| **11/08 12:51:55** | Cibele Heloisa (#107) se atribui a conversa → espelho cai | `human_takeover {"reason"=>"assignment","new_assignee_id"=>107}` |
| 11/08 12:52:03 | primeira fala humana: "Olá bom dia Bianca… sou Secretária Executiva" | msg 1622133 |
| 11/08 20:36:48 | resolvida | — |

**Espera até um humano falar: 18,70 h (1.122 min).** Handoff seg 14:09 local → humano ter 08:51 local.

### 22798 — Kelison · Pacaembu MCMV · paga R$ 1.500 de aluguel

| Hora (UTC) | O que aconteceu | Evidência |
|---|---|---|
| 10/08 15:55:22 | conversa criada (lead Meta `[FORMS] - PACAEMBU`), espelho da Júlia | `mirror_assigned` |
| 10/08 15:56–15:58 | três turnos de qualificação; cliente responde "Moro de aluguel" e "1500" | msgs 1618787/1618789 |
| 10/08 15:58:50 | novo turno → `reset_followup_state` zera o token | `debounce_fire` |
| **10/08 15:58:55** | `salvar_info_lead` + **handoff pela tool** — dossiê + marcador + time `vendas` (#26) | `AssistantLog handoff` + 2 `ToolCall status=ok` |
| 10/08 15:59:07→15:59:18 | IA continua e **deixa a pergunta no ar**: "você tem FGTS pra usar na entrada ou já juntou algum valor?" | msgs 1618792/1618793 |
| — | **silêncio de 20h02. Nenhuma cutucada. Nenhum humano.** | — |
| **11/08 12:01:25** | Cibele se atribui → espelho cai | `human_takeover {"reason"=>"assignment"}` |
| 11/08 12:01:47 | humano promete **outro** humano: "A corretora Francielli vai entrar em contato contigo 😊" | msg 1621704 |
| 11/08 19:46:06 | resolvida | — |

**Espera até um humano falar: 20,04 h (1.202 min).** Handoff seg 11:58 local → humano ter 08:01 local.

---

## 2. A causa provada: o token nunca foi armado

O caminho é o mesmo nas duas, e é uma sequência de três eventos dentro do **mesmo turno**:

```
ResponseBuilderJob#perform
  └─ reset_followup_state            (linha 14) → token da cutucada anterior zerado
  └─ generate_response_with_v2
        └─ HandoffTool#perform       → HumanHandoffService → aguardando_humano_desde = agora
  └─ process_response
        └─ create_messages           → a IA fala (e deixa uma pergunta no ar)
        └─ ensure_handoff_if_promised→ sai cedo (marcador já presente)
        └─ auto_schedule_followup    (linha 64)
              └─ ja_tem_destino?     (linhas 201-203) → aguardando_humano_desde presente → RETURN
```

`auto_schedule_followup` é o **único** produtor de cutucada preventiva. Ele volta antes de gerar o
token, antes de gravar `followup_status`, antes de enfileirar o `FollowupJob`. **Não há job.** Não há
nada para `owner_assistant` nem para `followup_pointless?` matarem depois — eles nunca foram
chamados.

### Como isso é provado, e não deduzido

`auto_schedule_followup` grava `followup_status = "cutucada auto-programada em ~120 min"` no mesmo
`update!` do token. O estado final das duas conversas é:

```
followup_token  = nil
followup_count  = 0
followup_status = nil
```

Essa tripla é **exatamente** o `zerado` do `reset_followup_state`. E depois do handoff nenhuma das
duas recebeu mensagem de cliente — logo nada pôde reescrever esses campos. Portanto o último a
tocá-los foi o reset do turno do handoff, e **`auto_schedule_followup` não escreveu nada depois
dele**. Se tivesse rodado até o fim, `followup_status` estaria com a frase da cutucada.

### Confirmação populacional

As **4 conversas que estão agora mesmo com `aguardando_humano_desde`** na conta 6:

| display | há | assignee | espelho captain | followup_token |
|---|---|---|---|---|
| 2159 | 4,4 h | nil | #18 | **nil** |
| 22855 | 2,1 h | nil | #17 | **nil** |
| 22891 | 1,7 h | nil | #20 | **nil** |
| 22902 | 1,0 h | nil | #18 | **nil** |

**4 de 4 com o espelho vivo e 4 de 4 sem token.** O dono continua sendo a IA — `owner_assistant`
devolveria a assistente sem problema. O que não existe é a cutucada. É o mesmo mecanismo, medido
fora das duas conversas do caso.

---

## 3. O que NÃO foi a causa (a hipótese, derrubada com dado)

| Hipótese do briefing | Veredito | Evidência |
|---|---|---|
| O espelho cai no handoff → `owner_assistant` nil → cutucada morre calada | **Falso nestes casos** | `human_takeover` só em 11/08 12:51 e 12:01 — 18h42 e 20h02 **depois** do handoff, e por atribuição manual da Cibele. `assignee_agent_bot` esteve presente o tempo todo no meio. |
| Quem zera o espelho é o `AssignmentService` via `HumanHandoffService` → `DistribuirService` | **Não ocorreu** | `Spx::Distribuicao::Policy` na conta 6: **0**. `distribuicao_logs`: **0**. O `DistribuirService` retorna `noop` na primeira linha (`return noop unless @team` passa, mas `Policy.for_team` devolve nil). Nenhuma linha de log nas duas conversas. |
| `followup_pointless?` matou a cutucada | **Não chegou a ser chamado** | Não havia job enfileirado. É a **segunda** tranca da mesma porta, não a que fechou. |

**A frase que resume a ironia precisa ser corrigida.** Não é "a IA emudece quando o rodízio
funciona" — é:

> **A IA emudece no instante em que promete um humano, e volta a falar só quando o humano chega.
> Se ele não chega, ela não fala nunca.**

O rodízio agrava isso no futuro (§8), mas hoje, na conta 6, ele está desligado e o silêncio
aconteceu assim mesmo. O `HandoffTool` chega a devolver ao modelo a instrução *"CONTINUE atendendo
normalmente até o atendente assumir de fato"* — e o Modelo A cumpre isso pela metade: a IA
**responde** se o cliente falar (`captain_can_respond?` não olha o marcador, só status e espelho),
mas **não inicia** nunca mais. Fala reativa sobrevive ao handoff; fala proativa é desligada por ele.
Como nos dois casos quem ficou com a bola foi o **cliente** — as duas últimas mensagens da IA são
perguntas —, meia sobrevivência equivale a nenhuma.

---

## 4. Havia compromisso armado? Não — e a "aresta aceita" é outro caso

`followup_motivo` está **ausente** nas duas, e o `captain_tool_calls` mostra **zero** chamadas de
`programar_followup` em ambas (22804: `buscar_imovel`, `enviar_fotos_imovel`, `handoff`,
`atualizar_resumo`; 22798: `salvar_info_lead`, `handoff`). Nenhum combinado morreu junto.

O que morreu foi a **cutucada preventiva** — a engrenagem 1 do contrato, sobrevida pura. A "aresta
aceita" registrada no fim de `docs/handoffs/spx-followup.md` fala da engrenagem 2 (compromisso
armado que fica suspenso quando um humano assume) e a declara **auto-curável pela tool**.

**Correção a esse texto, com base no código:** enquanto `aguardando_humano_desde` estiver presente,
**a tool não cura nada**. `ProgramarFollowupTool` grava `followup_token`/`followup_motivo` e
enfileira o `FollowupJob` sem consultar o marcador — arma normalmente. Mas na hora de disparar,
`FollowupJob#followup_pointless?` (linha 64-65) vê o marcador e mata. Ou seja: **um compromisso
combinado com o cliente durante uma espera por humano é armado e silenciosamente descartado.** As
duas trancas pegam engrenagens diferentes — `ja_tem_destino?` mata a cutucada preventiva na origem,
`followup_pointless?` mata o compromisso no disparo — e por isso consertar só uma delas não resolve.

---

## 5. O número que justifica o teto

### Nas duas conversas do caso

| | 22804 | 22798 |
|---|---|---|
| espera de relógio de parede | **18,70 h** | **20,04 h** |
| horário comercial do agente decorrido¹ | **≈ 4 h 42** | **≈ 4 h 31** |
| quem ficou com a bola | IA perguntou, cliente não voltou | IA perguntou, cliente não voltou |

¹ `assistant#13.behavior['business_hours']` está **ligado**: seg–qui (dias 1–4 confirmados no dump)
`07:30–11:30` e `13:30–17:30`, domingo sem faixa; a saída truncou os dias 5–6. 22804: seg 14:09→17:30
(3h21) + ter 07:30→08:51 (1h21). 22798: seg 11:58 cai no intervalo do almoço → 13:30→17:30 (4h) + ter
07:30→08:01 (31min).
*(A inbox 91 tem `working_hours_enabled=false` — a agenda que vale é a do agente.)*

**Quase 20 horas de relógio viraram 4 horas e meia de expediente.** Um teto de 6 h de relógio teria
disparado 00:09 da madrugada na 22804. É a regra 5 do contrato inteira num único número.

### Na população (30 dias, conta 6)

335 conversas com handoff. Das 293 que tiveram `human_takeover` depois:

| espera até o humano assumir | conversas | % |
|---|---|---|
| < 1 h | 153 | 52,2 % |
| 1–4 h | 53 | 18,1 % |
| 4–12 h | 21 | 7,2 % |
| **12–24 h** | **58** | **19,8 %** |
| 24–48 h | 7 | 2,4 % |
| > 48 h | 1 | 0,3 % |

mediana **0,78 h** · p75 **10,42 h** · p90 **15,49 h** · máx **48,81 h**

**+ 42 conversas com handoff e nenhum `human_takeover` até hoje** — a pior com **243,6 h** (10 dias).

A distribuição é bimodal: metade é atendida em menos de uma hora, e um quarto atravessa a noite.
Não é um problema de time lento; é um problema de **borda do expediente** — e é exatamente onde a
IA fica muda.

### O tamanho do vazamento

Do que aconteceu **depois** do handoff, nas 335:

| depois do handoff | conversas | % |
|---|---|---|
| cliente voltou, humano falou | 231 | 69,0 % |
| **cliente voltou, humano NUNCA falou** (só a IA atendeu) | **53** | **15,8 %** |
| cliente não voltou, humano falou | 21 | 6,3 % |
| **cliente não voltou e nenhum humano falou** | **19** | **5,7 %** |
| cliente voltou e **ninguém respondeu** | 2 | 0,6 % |

- **74 de 335 (22,1 %) nunca tiveram uma palavra humana** depois de a IA prometer uma pessoa.
- Das **19 em que o cliente sumiu e nenhum humano falou, 17 terminaram com uma pergunta da IA sem
  resposta** — o padrão exato da 22804 e da 22798. (Em 12 delas a IA ainda falou, mas apenas no
  mesmo turno do handoff, antes de o marcador desligar a cutucada.)
- **16 dessas 19 já estão `resolved`**: foram fechadas sem uma única palavra humana.
- Não confundir com as **42 sem `human_takeover`** citadas acima: aquelas são as que ninguém
  **assumiu**; estas 19 são as que ninguém **retomou**. Os conjuntos se cruzam, não coincidem.

Esse é o custo de não ter teto: ~6 leads por mês que a IA parou de cuidar, o humano nunca pegou, e
o sistema arquivou como resolvidos.

---

## 6. O volume de handoff mudou — a série passou a existir

O handoff da frente avisa que `handoff_auto_fired` **nunca havia disparado** em produção (o
`create!` levantava `RecordInvalid` e o `rescue` do chamador engolia). Confirmado, e agora existe:

| event_type | total histórico | primeiro registro | ritmo em agosto |
|---|---|---|---|
| `handoff` (log durável do `HumanHandoffService`) | **374** | **04/08/2026** — zero antes | 23–67/dia |
| `handoff_auto_fired` (safety-net) | **80** | **31/07/2026 21:34:53** | 2–14/dia (≈ 9 de média) |

Os dois se somam exatamente aos 454 eventos da janela de 30 dias, o que confirma que **todo
`handoff_auto_fired` vem acompanhado de um `handoff`**: o safety-net é um subconjunto do total, não
uma fila paralela.

Série diária de `handoff`: 04/08 **65** · 05/08 53 · 06/08 46 · 07/08 37 · 08/08 28 (sáb) · 09/08 23
(dom) · 10/08 **67** · 11/08 55.

Duas leituras que importam:

1. **O safety-net entrega hoje ~9 handoffs/dia que antes simplesmente não existiam.** São conversas
   em que a IA prometeu uma pessoa e ninguém era acionado. Elas agora entram na fila — e entram
   sujeitas ao mesmo silêncio descrito acima.
2. **As duas conversas do caso não vieram do safety-net.** As duas têm `AssistantLog handoff` +
   `ToolCall handoff status=ok` e **nenhum** `handoff_auto_fired`. Foi o agente chamando a
   ferramenta de propósito — o caminho mais "saudável" que existe. O buraco não está no atalho;
   está no caminho principal.

Quem assume, em 30 dias: Cibele Heloisa (#107) **523**, Gelson (#72) 243, Adrian (#63) 198, Evellyn
(#137) 169, Paloma (#71) 107. A concentração na secretária executiva explica a forma da curva: o
gargalo é uma pessoa que trabalha em horário comercial.

---

## 7. Proposta de teto

### O princípio

`aguardando_humano_desde` é hoje um **booleano eterno**. Precisa virar um **prazo**. Nenhuma das duas
trancas deve olhar "o marcador existe?"; as duas devem olhar "o marcador existe **e ainda está
dentro do prazo**?".

E o prazo tem que correr no **relógio comercial do agente** (`behavior['business_hours']`, que já
está configurado e ligado), não em horas corridas. Isso não adiciona um quarto relógio — ao
contrário, é a chance de **matar** o `QUIET_START`/`QUIET_END` hardcoded do `FollowupJob`, que hoje
ignora essa mesma agenda (dívida já registrada no contrato §4).

### Onde nada precisa mudar: a atribuição

`reset_agent_bot_when_assignee_present` **não é obstáculo nesta proposta**, e a evidência é direta:
nas 4 conversas hoje com o marcador, `assignee` é `nil` e o espelho captain está **presente**. A
conversa que estoura o teto é, por definição, a que **ninguém assumiu** — logo a IA já é a dona e
"a IA retoma" custa **zero mudança de atribuição**. O callback só morderia se alguém propusesse
atribuir a IA a uma conversa que já tem corretor; nenhuma opção abaixo faz isso.

O corolário é importante: **se houver `assignee` humano, o teto não é assunto desta frente** — a
conversa tem dono, o espelho já caiu, e quem cobra atraso é o SLA do rodízio.

### As opções, com custo

| | O que faz ao estourar | Custo / risco |
|---|---|---|
| **A · a IA retoma** | `ja_tem_destino?` e `followup_pointless?` passam a respeitar o prazo; a cutucada volta a ser armada, com diretiva **de sustentação** (retoma o ponto aberto, **não** repromete humano, **não** refaz handoff), limitada pelo `MAX_FOLLOWUPS` que já existe | A IA fala numa conversa prometida a uma pessoa — se o corretor entrar logo depois, há sobreposição de vozes. Mitigável pela diretiva e pelo prazo. **Volume:** ~2 a 3 conversas/dia com teto entre 4 e 12 h |
| **B · escalada interna** | nota privada + notificação ao time + devolve à fila "Aguardando atendimento" (a fila já existe: `conversation_finder.rb:359`) | Não fala com o cliente — **não estanca o vazamento**: as 19 em silêncio total continuariam em silêncio. E as notificações desta conta vêm **OFF de fábrica**, risco real de virar no-op. Custo ~zero |
| **C · limpar o marcador e devolver à IA** | apaga `aguardando_humano_desde`, tudo volta ao normal | Apaga o registro de que um humano foi prometido, some da fila do time, e a IA passa a agir como se nada tivesse sido combinado. **Descartada** |
| **D · não fazer nada aqui; deixar com o rodízio** | o SLA da `spx/rodizio` expira a designação e repassa a outro corretor | Hoje é **inerte** (0 políticas na conta 6). E repassar entre corretores não diz uma palavra ao cliente: as 19 continuariam mudas. Não resolve o problema desta frente |

### Recomendação

**A + B, nessa ordem, em dois degraus — e sempre o interno antes do externo.**

1. **Degrau 1 (interno), ao vencer `sla_assumir_minutos`:** nota privada + fila/repasse. Barato,
   reversível, e é exatamente a decisão que a frente já bateu para a *promessa esquecida do humano*
   ("escalada só interna, terminando na fila do time") — manter a mesma forma evita dois desenhos
   para o mesmo problema.
2. **Degrau 2 (externo), ao vencer `sla_retomada_minutos`:** a cutucada volta a ser armada, com
   diretiva de sustentação. Invariante obrigatória: **`sla_retomada_minutos >= sla_assumir_minutos`**
   — a casa sempre tenta resolver por dentro antes de a IA falar com o cliente.

**Números iniciais sugeridos para a Tozi:** degrau 1 em **60 min comerciais**, degrau 2 em **240 min
comerciais** (4 h de expediente). Nos dois casos investigados, o degrau 2 teria disparado por volta
de **17h de segunda** — mesmo dia, dentro do expediente, com o lead ainda quente, no lugar de 19 h de
silêncio. É deliberadamente conservador: começa perto da borda medida e aperta com dado.

**Honestidade sobre o número:** medi a distribuição em **relógio de parede**, não em relógio
comercial. Ela limita o degrau 2 por cima (no máximo 47,8 % dos handoffs, que é a fatia que passa de
1 h), mas não o determina. Antes de ligar, medir a mesma curva em horas comerciais — é o mesmo
script com uma função de calendário.

**Obrigatoriamente opt-in por conta, default off** (regra de produto da casa). Sugestão de forma:
os dois prazos vivem na `Spx::Distribuicao::Policy` do time (§8), e a ausência de política significa
comportamento de hoje — marcador eterno, exatamente como está. Nenhuma conta muda de comportamento
pelo merge.

---

## 8. NOTA DE COORDENAÇÃO — `spx/rodizio`

### O que aquela frente precisa saber

1. **Hoje o rodízio é no-op na conta 6.** 0 `Spx::Distribuicao::Policy`, 0 `distribuicao_logs`, em 335
   handoffs de 30 dias. O `DistribuirService` é chamado a cada handoff e volta `noop` no teste de
   política (`Policy.for_team` devolve nil). Nenhuma das 335 conversas foi distribuída por vocês.
   O piloto vai estrear nesse volume: **~54 handoffs/dia em dia útil** (média de 04–11/08 excluindo
   sáb/dom), **dos quais ~9/dia** vêm do safety-net que até 31/07 não existia.
2. **`modo_posse` decide se a cutucada sobrevive — e vocês são os donos dessa chave.**
   - `modo_posse: designacao` → o espelho captain **sobrevive**, `owner_assistant` devolve a
     assistente, e o teto desta frente funciona como proposto. É o mundo de hoje.
   - `modo_posse: assignee` → o `AssignmentService` grava o corretor e **solta o espelho no mesmo
     save**; o concern limpa `aguardando_humano_desde` na hora. A partir daí `captain_can_respond?`
     é falso e `owner_assistant` é nil: **o teto desta frente fica inerte por construção** — e está
     certo que fique, porque a conversa passou a ter dono humano. Aí o relógio que vale é o de
     vocês (corretor não engaja → repassa).
   - **Consequência prática:** quem cobra "ninguém assumiu" **muda de dono conforme o `modo_posse`**.
     Os dois lados não podem agir na mesma conversa.
3. **A designação sem assignee é justamente o buraco.** Em `designacao` ninguém vira `assignee`, e o
   marcador `aguardando_humano_desde` **nunca é limpo por vocês** — só quando um humano puxa a
   conversa à mão. É esse estado, o terceiro da SPEC-RODIZIO §3, que hoje dura 18 a 20 horas com a
   IA calada. O `sla_assumir_minutos` de vocês é a medida certa desse estado; falta a ação.
4. **O safety-net de handoff agora passa pelo `HumanHandoffService`** e portanto pelo
   `DistribuirService`: quando vocês ligarem uma política, esses ~9/dia entram no rodízio junto com
   o resto. Não há série histórica anterior a 31/07 para dimensionar — ela não existia.

### O que as duas frentes precisam decidir juntas

| # | Decisão | Por que não dá para decidir sozinho |
|---|---|---|
| 1 | **Um campo ou dois?** Proposta: **dois na mesma `Policy`** — `sla_assumir_minutos` (interno, repasse: já existe, default 30) e `sla_retomada_minutos` (externo, a IA volta a falar), com invariante `retomada >= assumir` | Um campo só obrigaria o mesmo instante para "trocar de corretor" e "a IA falar com o cliente". Aos 30 min default, a IA falaria meia hora depois de ter prometido uma pessoa — em 52 % dos casos o humano chega antes. Dois campos, um dono, ordem explícita |
| 2 | **Relógio de parede ou comercial?** Proposta: **comercial do agente**, e o `sla_assumir_minutos` passa a ser lido no mesmo relógio | Os 30 min de vocês e os 240 min desta frente só são comparáveis se correrem no mesmo calendário. Nas duas conversas, 20 h de parede = 4,5 h de expediente. Relógios diferentes = os dois disparam na hora errada |
| 3 | **Quem age em `modo_posse: assignee`?** Proposta: **só vocês** — esta frente sai de cena quando existe `assignee` | O `reset_agent_bot_when_assignee_present` já garante isso no código; a decisão é só torná-la explícita para ninguém construir o caminho morto |
| 4 | **Ordem do degrau 1 x designação.** Proposta: se a política já repassa a designação ao vencer `sla_assumir_minutos`, o degrau 1 desta frente **não repete** o repasse — vira só nota privada | Sem combinar, a mesma conversa pode ser repassada por vocês e devolvida à fila por mim no mesmo minuto |
| 5 | **A `Policy` é o lugar do opt-in?** Proposta: sim — sem política, comportamento de hoje | Se cada frente puser sua chave num lugar (`Policy` vs `account.settings`), ligar o rodízio e ligar o teto viram dois procedimentos com ordens próprias — e a frente já tem um incidente de ordem de chaves registrado no handoff |

**Pedido concreto:** antes de a `spx/rodizio` fixar o contrato da `Policy`, reservar o
`sla_retomada_minutos` (ou nome equivalente) no mesmo objeto. Se o campo nascer fora dele, esta
frente cria o segundo relógio que o contrato §4 proíbe.

---

## 9. Como reproduzir (tudo read-only)

Scripts usados, sem uma única escrita — só `find_by`, `where`, `pluck`, `count`:

```bash
# banner CLIENTE · AMBIENTE · HOST aparece antes de qualquer coisa
scripts/ops/tozi-prod.sh put <script>.rb /tmp/<script>.rb
scripts/ops/tozi-prod.sh run "bundle exec rails runner /tmp/<script>.rb 6 22804 22798"
```

| script | o que traz |
|---|---|
| `d_investiga.rb` | linha do tempo por conversa: mensagens, `AssistantLog`, `captain_tool_calls`, `distribuicao_logs`, episódios, `custom_attributes` e a idade do `aguardando_humano_desde` |
| `d_agregado.rb` | série diária de `event_type`, distribuição handoff→`human_takeover`, quem assume, população com o marcador, políticas de rodízio, config do agente |
| `d_vazamento.rb` | o que aconteceu depois do handoff por conversa (cliente/humano/IA falaram?), silêncio total, `business_hours` |

O `d_investiga.rb` é o `_dump.rb` da casa acrescido dos três blocos de auditoria
(`AssistantLog`, `ToolCall`, `distribuicao_logs`) — que são o que torna esta investigação
verificável, já que `aguardando_humano_desde` é transitório e some quando o humano assume.

## 10. Referências no código

| Ponto | Arquivo |
|---|---|
| a porta que fechou | `enterprise/app/jobs/captain/conversation/response_builder_job.rb:201-203` (`ja_tem_destino?`) |
| a segunda tranca | `enterprise/app/jobs/captain/conversation/followup_job.rb:64-66` (`followup_pointless?`) |
| a terceira, ainda desarmada | `enterprise/app/jobs/captain/conversation/followup_job.rb:19-20` + `:69-74` (`owner_assistant`) |
| quem escreve o marcador | `enterprise/app/services/captain/conversation/human_handoff_service.rb:28` |
| quem o apaga (e só ele) | `enterprise/app/models/enterprise/concerns/conversation.rb:40-60` |
| exclusividade corretor × espelho | `app/models/conversation.rb:370-374` |
| onde o `modo_posse` decide o espelho | `app/services/spx/distribuicao/distribuir_service.rb:205-213` |
