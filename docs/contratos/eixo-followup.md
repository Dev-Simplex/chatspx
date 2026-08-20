---
titulo: Contrato — as três engrenagens do eixo de follow-up
status: CANÔNICO · vocabulário e critério do eixo
dono: spx/followup
data: 2026-08-03
---

# Contrato — cutucada, follow-up e repescagem

> **Por que este arquivo existe:** enquanto o vocabulário não estiver escrito num lugar só, cada
> sessão o reinventa e as três engrenagens voltam a virar uma. Elas hoje compartilham código,
> estado e nome — e é dessa fusão que vêm os erros mais caros do eixo.
>
> Antes de mexer em qualquer coisa de follow-up: leia isto e use estes três nomes.

## 1. As três engrenagens

Elas se parecem porque todas "mandam mensagem pra quem sumiu". São diferentes em tudo o que
importa: **quem decide, que relógio corre, o que pode ser dito e quanto custa.**

| | **1 · CUTUCADA** | **2 · FOLLOW-UP** | **3 · REPESCAGEM** |
|---|---|---|---|
| **Para quê** | manter a conversa viva | cumprir o que ficou combinado | bater na porta de novo |
| **Dispara quando** | a IA falou, a bola ficou com o cliente e ele silenciou | o cliente sinaliza adiamento (com ou sem hora) | a janela fechou e 1 e 2 se esgotaram |
| **Relógio** | **relativo** — horas desde a última fala da IA | **absoluto** — o momento que o cliente deu | **dias** — desde a última mensagem do cliente |
| **Quem decide o conteúdo** | a IA, no contexto | a IA, no contexto | **o operador** — template aprovado e fixo |
| **Forma** | mensagem livre | livre se o momento cai dentro da janela; template se cai fora | template, sempre |
| **Vive** | só **dentro** da janela de 24h | dentro **ou** fora (muda a forma, não o compromisso) | só **fora** da janela |
| **Custo** | zero | zero dentro; pago fora | **pago por envio** |
| **Forma de repetição** | **escada**, intervalos crescentes | **não é escada** — cumprido uma vez, consumido | teto de **2 tentativas**, espaçadas 48h |
| **Cancela quando** | cliente responde de verdade · humano assume · conversa resolve · **janela fecha** | o combinado é cumprido. **Despedida educada NÃO cancela** | o cliente responde — o que reabre a janela e devolve o caso a 1 e 2 |

### A regra que organiza as três

> **Template não reabre a janela. Só a resposta do cliente reabre.**

Por isso repescagem **não é recado**: é batida na porta cujo único trabalho é **conseguir
resposta** — porque a resposta é que compra 24h de conversa livre. Um template caprichado que
informa tudo e não pede nada é dinheiro gasto para manter a porta fechada.

## 2. Sete regras que evitam dor de cabeça

1. **A borda da janela separa as engrenagens.** 1 e 2 vivem dentro, 3 vive fora, nenhuma
   atravessa. Cutucada fora da janela **não é repescagem disfarçada — é bug.** O `FollowupJob`
   para na borda; não cai em outro caminho de envio.
2. **Cada engrenagem precisa do próprio estado.** Um `followup_token` só já limita hoje: o
   cliente diz "me chama às 20h" e some às 15h — não dá pra cutucar às 18h **e** honrar as 20h.
   Hoje o compromisso vence e a cutucada preventiva fica suspensa; isso é remendo, não desenho.
3. **A âncora é sempre a última mensagem do CLIENTE.** É ela que define a janela. Ancorar na fala
   da IA faz o cálculo derivar a cada cutucada — e a derivação é sempre no sentido de achar que
   ainda há janela quando já não há.
4. **Auto-resposta não é engajamento.** 9,4% das respostas na base de motoristas são robô de
   negócio. Tratar isso como reengajamento reinicia escada e contamina qualquer medição.
5. **Horário tem três relógios, e hoje viraram um:** (a) quando a IA pode **iniciar** — cutucar é
   interromper, responder não é; (b) quando existe **humano para assumir**; (c) o **horário que o
   cliente pediu**, que pode estar fora dos dois. Confundi-los produz tanto o silêncio no fim de
   semana quanto a cutucada às 22h.
6. **"Esperando humano" precisa de teto.** Hoje é estado eterno que cala a IA — 36 horas de
   silêncio num fim de semana (conversa 20713).
7. **Cada uma liga e desliga sozinha.** Desligar repescagem não pode desligar cutucada.

## 3. Estado de cada engrenagem no código

### 1 · Cutucada — existe e funciona
`auto_schedule_followup` (`ResponseBuilderJob`) + `FollowupJob`. Escada com `MAX_FOLLOWUPS = 4`,
intervalo único de `followup_auto_minutes` (default **120**, e `behavior.followup` está `{}` nas
8 assistentes, então todas caem no default).

**Falta:** parar na borda da janela (o `FollowupJob` **não checa `can_reply?` em lugar nenhum**) e
a última cutucada **~2h antes do fecho** — a de maior alavancagem, porque é a última grátis e a
urgência é verdadeira.

### 2 · Follow-up — existe, com o relógio errado
`programar_followup` (115 chamadas em 30 dias, medidas em `captain_tool_calls.args`). O código já
distingue as duas engrenagens pelo **`followup_motivo`**, que só essa tool escreve — é esse campo
que separa "compromisso" de "sobrevida" no `FollowupJob` e no `reset_followup_state`.

**Falta:** o momento do cliente mandar no relógio. Hoje o modelo **chuta minutos** e escolhe o
teto de 2880 em ~30% dos casos; 41 de 115 pedem além das 24h da janela. O parâmetro `janela`
(palavras do próprio cliente) está pronto em `3be2381ce` na **spx/fricoes** e **não deployado** —
o dono do contrato daquela tool é a fricoes; esta frente parte dele, não o reimplementa.

### 3 · Repescagem — não existe
**Zero código.** Os templates `tozi_lead_reativacao`, `tozi_lead_followup` e
`tozi_followup_horario_combinado` estão **aprovados e sem uso**.

## 4. Onde as engrenagens ainda estão fundidas (dívida conhecida)

- **Um token para duas engrenagens** (regra 2). `followup_token` é único; compromisso e cutucada
  disputam o mesmo slot.
- **Quiet hours hardcoded** — `QUIET_START = 21` / `QUIET_END = 8` como constantes no
  `FollowupJob`, ignorando o `business_hours` do assistente, que está **configurado e ligado** nas
  7 assistentes ativas (America/Cuiaba, 7 dias, com `outside_hours_action`). É a regra 5 fundida.
- **`followup_pointless?` sem teto** — `resolved? || aguardando_humano_desde.present?`. É a regra
  6: o marcador assume que a pessoa vem.
- **O espelho cai na designação, não no handoff.** `bot_handoff!` **não** solta o espelho; quem
  zera `assignee_agent_bot` é o `Conversations::AssignmentService`, alcançado via
  `HumanHandoffService` → `Spx::Distribuicao::DistribuirService`. Ou seja: **a IA emudece
  exatamente quando o rodízio funciona.** E `reset_agent_bot_when_assignee_present`
  (`before_validation`) proíbe conversa ter corretor atribuído **e** espelho ao mesmo tempo —
  então "a IA retoma" não é uma flag, é uma decisão sobre atribuição.
  ⚠️ Cruza com a **spx/rodizio**: `sla_assumir_minutos` (default 30) já existe na policy dela,
  declarado como **medida, não ação**. Um segundo relógio aqui diverge do dela. A ação sobre esse
  limiar precisa ser combinada entre as duas frentes.

## 5. Como usar este contrato

- Nome errado é bug de comunicação que vira bug de código: **cutucada**, **follow-up** e
  **repescagem** são três coisas, e nenhuma é "o follow-up".
- Antes de acrescentar campo de config, pergunte **de qual engrenagem** ele é. Se servir às três,
  provavelmente está no lugar errado.
- Antes de acrescentar caminho de envio, pergunte **de que lado da borda** ele vive.
