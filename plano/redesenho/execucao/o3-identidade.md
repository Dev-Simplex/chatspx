> # ⛔ AGUARDA DECISÃO SUA — e o canal do Orca não estava disponível
>
> **Não consegui entregar `escalation` nem `worker_done` desta trilha.** O dispatch
> `ctx_e9e07b2b6422` está **revogado** (já usei o `worker_done` dele na Onda 1) e a nova
> tarefa chegou **sem dispatch novo**; `orchestration task-list` responde `run_required`.
> Não vinculei um Run por conta própria de propósito: isso fabricaria provenance, que é
> justamente o que o guia manda não fazer. **Este arquivo é o canal.**
>
> ## A decisão que é sua
>
> Você pediu para eu não decidir sozinho se fechar `POST /api/v1/widget/conversations`
> muda integração de cliente existente. **Muda, e de forma severa** — por isso NÃO fechei
> por 401:
>
> Fechar por 401 **desligaria a coleta de e-mail do pré-chat inteira** em toda inbox
> estrita, porque o visitante **não tem como assinar**: o segredo do HMAC é do servidor do
> cliente. Isso não seria enforcement, seria remover uma funcionalidade.
>
> **O que fiz no lugar** (4.16): a recusa é do **merge**, não da requisição, e só quando o
> campo pertence a **outro** cadastro. Visitante novo não é afetado em nenhum estado.
>
> **A consequência que você decide:** sob estrito, o visitante que volta e digita um e-mail
> já cadastrado **não recebe mais o histórico de volta** — começa conversa nova.
>
> **O número**, por inbox, em produção, sem mudar comportamento:
> ```ruby
> Identity::EnforcementReport.new(inbox: Inbox.find(ID)).perform
> ```
> `unverified.total` é o universo que a virada atinge. Sessão anônima fica **fora** da
> conta de propósito — incluí-la inflaria o número com visitante que o estrito nem recusaria.
>
> **Minha recomendação:** ligar `observado` nas inboxes de maior tráfego, deixar rodar, e só
> então decidir a virada com o número na mão. Enquanto isso o 4.16 já protege o caso do
> atacante.

---

# Onda 3 · Trilha IDENTIDADE E ENFORCEMENT — relatório de execução

- Worktree: `/home/chatwoot/chatwoot-o1-backend` · branch `o1-backend`
- Base: merge de `redesenho-integra` (`8f2eae7c7a`), sem conflito
- Banco de teste dedicado: `chatwoot_test_o3ident`
- Blocos: **4.15 · 4.16 · 4.17** — todos fechados

## Estado

| Bloco | Estado | Commit | Número medido |
|---|---|---|---|
| 4.15 | ✅ fechado | `1796ed9a58` | 29 examples / 28 failures → **44 / 0** |
| 4.16 | ✅ fechado | `c7fcefcb6f` | 11 / **4 failures** → **11 / 0** |
| 4.17 | ✅ fechado | `63f62f3208` | prompt 9/8 e portão 9/7 → **0** nos dois |

**Portão final dos três blocos: 170 examples, 1 failure** — e ela é o `toggle_status`
herdado da base, confirmado falhando no HEAD limpo.

---

## Achado sobre a base recebida

O merge trouxe **7 dos meus 8 commits da Onda 1**. Faltava exatamente o último,
`4c9bf1c27a` — o que corrige a linha "Endereço IP" que nunca renderizava para ninguém.
O merge o reintroduziu, então nada se perdeu, mas **`redesenho-integra` não o continha**.

E a base **não está com 5.361 verdes** neste worktree. Medido, sem nenhuma alteração minha:

| Suíte | Falhas no HEAD limpo | Causa |
|---|---|---|
| `spec/enterprise/services/captain/llm` | **69** | `WebMock::NetConnectNotAllowedError` — os specs tentam bater em `api.openai.com` |
| `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb` | 7 | pré-existentes |
| `spec/models/inbox_spec.rb:45` | 1 | `account.delete` viola FK de `funnels` (sem cascade) |
| avatar job ×2, `toggle_status`, dyte | 4 | as mesmas já documentadas na Onda 1 |

As 69 do enterprise merecem atenção do coordenador: são specs que **tentariam chamar a
OpenAI de verdade** se o WebMock não estivesse barrando.

---

## 4.15 — Três estados de enforcement · `1796ed9a58`

`desativado` / `observado` / `obrigatorio`, em `inbox.additional_attributes` pela
convenção do 3.01 — sem coluna e sem migration.

### `hmac_mandatory` como PISO, não como sinônimo

O aceite pedia "mantendo `hmac_mandatory` como está". A resolução o lê como piso:

```ruby
return STRICT if channel.try(:hmac_mandatory)
```

Não existe caminho por onde escrever no jsonb **afrouxe** uma inbox que hoje exige
assinatura. Nenhuma inbox da frota muda de comportamento por causa deste bloco.

### Duas coisas que o bloco corrigiu ao ser desenhado

**1. A armadilha do `hmac_verified`.** Sob `observado`, `should_verify_hmac?` fica
verdadeiro e a linha que marca a sessão como verificada teria marcado uma sessão **sem
assinatura conferida** — apagando o único sinal de que o relatório depende. Passou a
exigir `should_verify_hmac? && valid_hmac?`. Para `desativado` e `obrigatorio` é
equivalente ao que já acontecia.
Medido isolando só essa guarda: **1 vermelho** (`expected false, got true`).

**2. Não havia como LIGAR o estado.** `additional_attributes` tem lista branca por chave
no `inboxes_controller`, e chave fora dela é descartada em silêncio pelo strong
parameters. Entrou `:identity_enforcement`.
**Não** entrou `identity_enforcement_observed_since`: quem pudesse gravar a marca de
início da observação moveria o corte do relatório e faria o número que decide a virada
mentir. A marca é do modelo e nasce na transição. Coberto por teste.

### O relatório que produz a lista

`Identity::EnforcementReport`, **derivado** de `contact_inboxes.hmac_verified`, não de log
— log rotaciona, se perde e não se conta. Duas regras contra mentir, as mesmas do
`Tracking::OriginReport`:

- **sessão anônima não entra**: não tem identidade para verificar, e contá-la inflaria o
  número que decide a virada;
- o que antecede a observação sai em `before_observation`, nunca somado ao medido e
  **nunca zerado** — sem marca de início os campos vêm `nil`, porque zero seria lido como
  "não houve nenhuma" onde houve tráfego sem ninguém anotando.

---

## 4.16 — Portas 3 e 4 · `c7fcefcb6f`

`POST /widget/conversations` e `PATCH /widget/messages/:id` chamavam o
`ContactIdentifyAction` sem identifier e sem assinatura. Como `merge_contacts?` devolve
`true` sempre que `params[:identifier]` está em branco, **os dois fundiam
incondicionalmente**.

### A recusa é do MERGE, não da requisição

Isto é a decisão central do bloco, e é deliberada: **não existe como o visitante assinar**
— o segredo do HMAC é do servidor do cliente. Recusar a requisição desligaria a coleta de
e-mail do pré-chat inteira, inclusive para o visitante novo, que não tem nada a ver com o
problema. O dano não está em o visitante se identificar; está em **absorver um cadastro
existente**.

E a regra é estreita: só morde quando o campo pertence a **outro** cadastro.

Sob estrito também não se reivindica o campo — reivindicar bateria no índice único
`uniq_email_per_account_contact` e derrubaria a criação da conversa. O e-mail digitado não
se perde: no `input_email` ele já fica em `submitted_email`.

### Propriedade que caiu de graça

Sob `observado` a fusão acontece, e ela **já aparece no relatório do 4.15 sem mecanismo
novo**: deixa o `contact_inbox` do dono com `hmac_verified: false` e o dono tem e-mail —
exatamente a linha que o relatório conta. Coberto por teste.

**Vermelho medido: 4 falhas**, todas as asserções de estrito das duas portas. O exemplo
"cria a conversa" **já passava no vermelho**, o que confirma que a correção não passou a
recusar requisição.

---

## 4.17 — Origem, confiança e o prompt da IA · `63f62f3208`

### A migration

Duas colunas **sem default e sem `null: false`**. A cicatriz é real: restrição
acrescentada sobre linha existente passa no banco de teste vazio e falha na frota. Sem
default não há reescrita de tabela; sem NOT NULL não há linha antiga violando a regra no
instante do ALTER. `nil` tem significado nas duas (A4, sem backfill). Índice **parcial**,
só sobre as protegidas.

### O selo do 1.17 ficou durável

`auto_provisioned_from_website?` passou a ler a coluna. Antes dependia de casar o **texto**
da descrição — o agente que editasse a descrição apagava sem querer a informação de onde o
dado veio. Definição anterior à coluna continua respondendo pela descrição, senão o selo
sumiria de toda linha antiga no dia da migration.

### O buraco que o teste de ponta a ponta encontrou

O endpoint de conversa é de **substituição**. Recusar a escrita da chave protegida não
bastava: bastava **omiti-la** para apagá-la. Apagar também é alterar. Agora toda chave
protegida que já existia sobrevive, tenha vindo no payload ou não — e a substituição segue
valendo byte a byte para tudo que não é protegido.

### O prompt

O bloco de contato inteiro é escrito pelo visitante e pelo site: `name` vem do pré-chat e
os atributos vêm de `setCustomAttributes`. Agora vai dentro de `<contact_data>` com
política explícita de que aquilo é dado, nunca instrução — e **o delimitador é removido do
próprio valor**, senão um atributo contendo `</contact_data>` fecharia a marcação no meio
do prompt e o resto voltaria a ser lido como instrução.

**Dry run, como o aceite exige**: os exemplos constroem a string e afirmam sobre ela.
Nenhuma chamada a modelo, nenhuma IA de cliente.

A invariante medida é a tag **ancorada em linha**, e não a contagem de ocorrências: a
política nomeia a tag no meio do texto de propósito, então contar ocorrências soltas
mediria a política, não a marcação. E valor nenhum consegue produzir uma tag ancorada,
porque `sanitize_attr` tira as quebras de linha antes.

---

## A porta que eu tinha achado, e a decisão que NÃO tomei sozinho

Está escalado ao coordenador. Resumo do que medi:

**Fechar `POST /widget/conversations` com 401 mudaria integração de cliente existente** — e
de forma severa: desligaria a coleta de e-mail do pré-chat em toda inbox estrita, porque o
visitante não tem como assinar. Por isso **não** foi o que fiz.

O que o 4.16 faz muda uma coisa visível, e essa é a decisão de produto: **o visitante que
volta e digita um e-mail já cadastrado, numa inbox estrita, não recebe mais o histórico de
volta.** Ele começa uma conversa nova.

O número que decide isso é exatamente o que o estado `observado` existe para produzir, e
ele se lê por inbox em produção:

```ruby
Identity::EnforcementReport.new(inbox: Inbox.find(ID)).perform
```

`unverified.total` é o universo que a virada para estrito atinge;
`unverified.since_observation` é o que foi medido depois de a observação começar.

---

## Cicatrizes desta execução

- **Banco de teste ficou inválido.** Rodar `db:migrate` e um `rspec` em paralelo
  interrompeu um `DROP DATABASE` e o PostgreSQL marcou `chatwoot_test_o3ident` como
  *invalid* — o sintoma foi `NoDatabaseError` num estado e sucesso no outro, o que parecia
  bug de código. `dropdb --force` + recriar resolveu. **Não rodar migration concorrente com
  suíte no mesmo banco.**
- **`0 examples, 0 failures` passou por verde duas vezes** durante as medições de vermelho,
  quando o arquivo de spec não carregava por constante ausente. Todo vermelho deste
  relatório foi remedido com N > 0.
