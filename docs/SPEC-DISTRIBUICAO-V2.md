# Spec — Distribuição v2 (o rodízio como módulo de produto)

> Revisão da [`clientes/tozi/SPEC-RODIZIO.md`](clientes/tozi/SPEC-RODIZIO.md), que segue válida no
> que descreve o motor. Esta spec trata do que a v1 **não** resolveu: fazer a distribuição existir
> fora da IA, ser configurável por quem convive com a equipe, e servir qualquer cliente.
>
> Escrita em 24/08/2026 a partir de medição na produção da Tozi (conta 6), não de suposição.

---

## 1. Por que existe uma v2

A v1 entregou o motor e **nunca rodou**. Os fatos, medidos:

| fato | número |
|---|---|
| `distribuicao_policies` / `states` / `logs` / `produtos` | **0 linhas cada** |
| Pontos de chamada do `DistribuirService` | **1** — dentro do `HumanHandoffService` |
| Tela `RodizioPage.vue` em produção | desde 31/07 |
| Entradas de menu que levam a ela | **0** — só por URL digitada |

Três consequências:

1. **A distribuição é hoje uma funcionalidade da IA, não do produto.** Conversa que não passou por
   um agente de IA — inbox sem IA, disparo, conversa aberta por humano, órfã — nunca vê o motor.
   Cliente sem IA não tem distribuição nenhuma.
2. **Não existe como configurar.** Policy só por console. Quem sabe que alguém entra de férias na
   semana que vem é o gerente, e ele não tem tela.
3. **Não existe como ligar com segurança.** Ou o motor atribui de verdade, ou não roda. Não há
   modo de observação.

---

## 2. As quatro dimensões

O erro de modelagem da v1 foi tratar "rodízio" como uma coisa. São quatro decisões independentes,
e hoje três estão coladas dentro do mesmo serviço.

| # | dimensão | pergunta | estado |
|---|---|---|---|
| ① | **Gatilho** | *quando* distribuir | 🔨 só handoff da IA |
| ② | **Elegibilidade** | *quem pode* receber | ⚠️ pool e teto existem; falta suspensão com prazo e escala |
| ③ | **Escolha** | *qual deles* | ✅ preferência → continuidade → ponteiro |
| ④ | **Posse** | *o que acontece* depois | ⚠️ `assignee` e `designacao` existem; falta `sugestao` |

### ① Gatilho — configurável por conta

```
gatilhos: [handoff_ia, conversa_sem_dono, conversa_reaberta, orfa, resposta_de_campanha]
```

`handoff_ia` é o de hoje e continua sendo o default. Os outros são o que faz o módulo existir sem
IA. O `Conversations::OrphanRetriageJob` já roda de 15 em 15 minutos e é o lugar natural do gatilho
`orfa` — não precisa de cron novo.

### ④ Posse — o terceiro modo

| modo | efeito | quando usar |
|---|---|---|
| `assignee` | atribui; a IA cala | time que vive no SPX |
| `designacao` | registra; a IA continua até alguém assumir | time que vive fora (vendas → Vista) |
| **`sugestao`** 🔨 | **registra e avisa; não move nada** | **ligar em cliente novo sem risco** |

`sugestao` é o modo de sombra: o motor decide, grava no log, e o humano continua distribuindo à mão.
Depois de uma semana compara-se o que o motor escolheria com o que o time fez. É a única forma
honesta de ligar distribuição automática num cliente sem histórico.

---

## 3. Elegibilidade — suspensão com prazo

Hoje a entrada do pool tem só `ativo: true|false`. Isso obriga alguém a **lembrar de desfazer**
depois das férias — e ninguém lembra. Regra que já aprendemos em outra frente: **exceção tem data e
morre sozinha.**

```jsonc
{
  "user_id": 137,
  "ativo": true,
  "suspenso_ate": "2026-08-30",   // NOVO — nulo = sem suspensão
  "motivo": "férias",             // NOVO — só para o humano lembrar
  "cap": 20,
  "produtos": [{ "produto": "terceiros", "valor_max": 600000 }]
}
```

| estado | como fica | expira sozinho? |
|---|---|---|
| Ativo | recebe normalmente | — |
| **Suspenso até `<data>`** | pulado; volta sem intervenção | ✅ |
| Desativado (`ativo: false`) | fora até religarem | ❌ |

Os dois convivem: suspensão é temporária e prevista; desativação é indefinida (saiu da equipe, está
sendo punido). `Policy#pool_entries` passa a filtrar os dois.

---

## 4. Escolha — a cascata (já implementada)

```
preferência do cliente  →  continuidade  →  rodízio (ponteiro, pulando teto)
```

**Preferência** (`preferencia_do_cliente`) — casa por id, nome completo ou primeiro nome **único**;
ambíguo devolve nada de propósito. **Consome a vez**: se não consumisse, bastaria o corretor dizer
"peça por mim" para furar a fila que o rodízio existe para impedir.

**Continuidade** (`consultor_anterior`) — mesmo contato, **mesmo time**, dentro da janela, e que
**ainda esteja no pool ativo**; pega o mais recente por `last_activity_at`. **Não consome a vez** —
retorno não é lead novo. Não cruza time de propósito.

⚠️ **Duas limitações honestas:**
- Lê `assignee_id`: é *quem foi atribuído*, não *quem falou*. Na locação da Tozi isso empata (96%
  das atribuições viram fala), então serve. Em outro cliente pode não servir.
- **Não funciona em `modo_posse: designacao`**, porque `assignee` nunca é gravado. Em vendas a
  fonte de "quem já atende este cliente" é o Vista.

---

## 5. O escritor da preferência (a tool)

O campo `rodizio_preferencia` é lido pelo motor e **hoje ninguém o escreve** — o desvio é inerte
desde 31/07.

Tool nova, genérica: **`registrar_preferencia_atendente`**

| param | descrição |
|---|---|
| `nome` | o nome **como o cliente falou**, sem normalizar |

Regras de conduta que acompanham:
- Só chama quando o cliente **pede** por alguém. Mencionar não é pedir.
- **Nunca confirma o nome ao cliente.** Registra e segue. Quem responde se apresenta.

> **Por que não confirmar:** a pessoa pode estar suspensa, fora do pool ou o nome pode ser ambíguo —
> nos três casos o lead cai no rodízio. Prometer nome é a forma mais barata de criar frustração.

⚠️ **REGRA #1** — a descrição da tool não pode conter nome de exemplo. Nome concreto em descrição de
ferramenta vira valor copiado (já aconteceu: `(ex: 6573)` fez a IA mandar sempre o imóvel 6573).

---

## 6. Repasse por tempo de resposta

`sla_assumir_minutos` existe e **só mede**. Campos novos na policy:

| campo | default | o que faz |
|---|---|---|
| `repasse_automatico` | `false` | ao estourar o SLA, passa para o próximo |
| `max_repasses` | `3` | depois disso, para de circular |
| `pool_esgotado_destino_user_id` | nulo | dono final; circular para sempre = ninguém responsável |
| `sla_respeita_horario` | `true` | relógio congela fora do expediente **do time** |
| `expirado_conta_como_recebido` | `true` | **a punição vira aritmética** |

O último é o mais importante e o menos óbvio: quem deixa vencer **gastou a vez** e vai para o fim da
fila igual a quem atendeu. Recebe menos lead sozinho, sem ninguém aplicar penalidade. Com `false`,
ignorar lead é de graça.

⚠️ `sla_respeita_horario` exige saber o expediente **do time**. O Chatwoot tem `working_hours` por
**inbox**, não por time. Enquanto não houver expediente por time, o campo cai no da conta — e isso
fica declarado, não escondido.

---

## 7. Papéis: admin · gerente · agente

O backend **não ganha role nova**. O fork já decidiu que *"Supervisor é rótulo de UI, não role do
backend"* (`task/supervisor-de-time.md`, D1/D6), e a mesma decisão vale aqui.

| papel (UI) | backend | enxerga | pode |
|---|---|---|---|
| **Admin** | `administrator` | conta inteira | configurar tudo |
| **Gerente** | `agent` + `team_supervisors` | só os times que supervisiona | responder pelo time · relatório escopado · gerenciar membros · **e o pool da distribuição** |
| **Agente** | `agent` (+ custom role) | o que é dele | atender |

**O dono do pool é o gerente.** A frente Supervisor já entrega *"supervisor gerencia a composição do
time"* (F5); o pool é a extensão natural — quem sabe quem entra de férias convive com a equipe.

⏳ **Dependência declarada:** "gerente" só fecha quando os relatórios forem **escopados por
supervisão**, hoje em *Fora de escopo (deferido)*. Sem isso, gerente é um agente cego.

---

## 8. Front — dentro do time, não em página à parte

A configuração mora em `/accounts/:id/settings/teams/:teamId/edit`, que **já é um wizard**
(`woot-wizard` + `router-view`) com dois passos. Distribuição entra como **terceiro passo**, sem
navegação nova.

```
① Dados    ② Membros    ③ Distribuição
```

O passo ③ expõe, nesta ordem: ligar/desligar · critério (rodízio · menor carga · só sugerir) ·
continuidade (com janela) · respeitar pedido do cliente · tempo para assumir e o que fazer ao
estourar · destino final · e a **lista ordenável do pool**, cada linha com estado, prazo de
suspensão, motivo e teto.

A tela de contabilização (`RodizioPage.vue`) continua existindo e **entra no menu** — hoje está no
ar e é inalcançável.

---

## 9. Ordem de entrega

| # | fatia | destrava |
|---|---|---|
| 1 | **Suspensão com prazo** + campos novos da policy | o pool passa a ter semântica de gente de verdade |
| 2 | **Tela no time** (API + passo ③) | o gerente configura sem console |
| 3 | **Tool da preferência** | a regra ① sai do papel |
| 4 | **Repasse por SLA** | o SLA vira ação, não só número |
| 5 | Gatilhos além do handoff · modo `sugestao` | o módulo existe sem IA |

**A ordem inverte a v1 de propósito:** a v1 mandava começar por vendas; vendas é o time que **não
pode** ser ligado hoje (2 membros, nenhum corretor, `build_pool` intersecta com membros → pool vazio
em silêncio). Locação é onde o dado diz que funciona.

---

## 10. Fora desta spec

- **Escala e turnos** no pool — dimensão nova, onda própria.
- **Comissionamento** — a v1 sabe contar lead *recebido*, não lead *atendido*.
- **Punição automática** — depende do sinal de engajamento da `spx/eval`.
- **Continuidade em vendas pelo Vista** — entra junto com o espelho, não aqui.
- **Expediente por time** — hoje o Chatwoot só tem por inbox (ver §6).

---

## 11. Correção de registro

A âncora #9 da v1 diz *"locação e administrativo já rodam hoje com o motor distribuindo — não mexer
no que funciona"*. **Em locação não roda nada**: quem distribui é uma pessoa, à mão — medido em
744 conversas tocadas a 1,7 mensagem cada em 90 dias. Isso não invalida a v1; significa que ligar a
locação tem **menos** risco do que ela supunha, e é por isso que a ordem foi invertida.
