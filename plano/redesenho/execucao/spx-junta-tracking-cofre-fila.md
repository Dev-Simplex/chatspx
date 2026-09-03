# A junta: a fila de tracking ligada ao cofre de credenciais (5.02 × 5.11/5.12/5.13)

**Worktree:** `/home/chatwoot/chatwoot-spx-junta-tracking` · **Branch:** `spx-junta-tracking`
**Base:** `homologacao` (`6d56c722c8`) · **Data:** 24/08/2026

**O problema:** as duas trilhas pararam na fronteira uma da outra. O cofre chegou; o
`Tracking::CredentialResolver` devolvia `nil` fixo e a fila inteira estava **inerte**. Fechada.

---

## 0. Duas coisas achadas antes da primeira linha de código

### 0.1 A worktree nasceu de `develop`, não de `homologacao`

A task nomeia `homologacao` (`7b4ad0a371`). A worktree estava em `6a7cbcf5ba`, que é o topo de
`develop` — **e não é ancestral de `homologacao`**. Nenhum dos dois arquivos que a task manda ler
existia ali: nem `credential_resolver.rb`, nem `tracking_credential.rb`. Escrever a junta naquela
árvore teria produzido um arquivo novo contra um modelo inexistente.

A branch não tinha commit próprio e a árvore estava limpa, então alinhei com `git reset --hard
homologacao`. Nada foi perdido. `homologacao` já havia avançado de `7b4ad0a371` para `6d56c722c8`
— dez commits, entre eles os **merges das duas trilhas** que esta task junta, então é a base certa.

### 0.2 O contrato assumido pela fila **não casa** com o modelo entregue

A escalação da trilha da fila registrou o contrato: *"um registro por (account_id, inbox_id), com
`inbox_id` nulo valendo como padrão da conta"*, e dez leitores em claro. Conferido contra a tabela
que chegou, **duas diferenças, e as duas mudam comportamento**:

| O que a fila assumiu | O que o modelo entregou |
|---|---|
| `inbox_id` nulo = padrão da conta | `inbox_id` **NOT NULL**, com UNIQUE — linha de conta é impossível |
| 10 campos, todos no cofre | 4 no cofre; os IDs públicos moram em `inbox.additional_attributes['widget_tracking']` (5.01) |

O ajuste foi **do lado do resolver**, como a task determina: o modelo tem spec e aceite passado.

---

## 1. O que a junta faz agora

`Tracking::CredentialResolver` junta as duas metades, e é o **único** lugar da fila que fala com
`TrackingCredential` — os destinos e os jobs continuam recebendo um `Settings` e não sabem de onde
ele veio.

| Campo do `Settings` | Fonte | Estado |
|---|---|---|
| `meta_pixel_id` | `widget_tracking['meta_pixel_id']` | ✅ liga |
| `meta_access_token` | cofre (cifrado) | ✅ liga |
| `meta_test_event_code` | cofre | ✅ liga |
| `ga4_measurement_id` | `widget_tracking['ga4_measurement_id']` | ✅ liga |
| `ga4_api_secret` | cofre (cifrado) | ✅ liga |
| `google_ads_developer_token` | cofre (cifrado) | ✅ liga |
| `google_ads_access_token` | — | ⛔ sem fonte (§3) |
| `google_ads_customer_id` | — | ⛔ sem fonte (§3) |
| `google_ads_conversion_action_id` | — | ⛔ sem fonte (§3) |
| `google_ads_login_customer_id` | — | ⛔ sem fonte (§3) |

**Meta CAPI e GA4 Measurement Protocol entregam.** Google Ads continua fora do leque — sem inventar
credencial, e sem montar um payload que a API recusaria.

### 1.1 A credencial é a âncora

Sem linha no cofre, o retorno é `nil` e a fila fica inerte — **mesmo com o Pixel ID configurado na
inbox**. Id público sozinho não escreve nada em destino nenhum: o que escreve é o token, e ele só
existe no cofre.

### 1.2 A resolução é estritamente por inbox

Não há herança da conta, porque não há linha de conta. Evento sem inbox não resolve credencial de
ninguém — inventar uma herança aqui faria o evento de uma inbox sair pelo pixel de outra. O
`find_by` filtra por `account_id` **e** `inbox_id`, redundante com a validação do modelo de
propósito: o UNIQUE do banco é só em `inbox_id`, então esta é a única barreira que sobreviveria a
uma linha gravada por console ou import com a conta errada.

---

## 2. Os testes, e por que eles não passam no vácuo

Este é o coração da task. **Toda a suíte da trilha da fila dubla o resolver**
(`allow(Tracking::CredentialResolver).to receive(:call)`) — legítimo para testar backoff e DLQ
isoladamente, mas deixava um buraco exato: nenhum exemplo provava que uma credencial real produz uma
entrega, e "sem credencial não entrega" passava **por ausência de sujeito**.

Os dois arquivos novos não dublam nada além do cliente HTTP: o `TrackingCredential` é gravado, o
`widget_tracking` é gravado, e o que se mede é o POST que chega ao dublê.

### 2.1 As quatro provas de vermelho

Quebrei cada proteção e registrei a falha observada:

| # | Quebra aplicada | Falha observada |
|---|---|---|
| 1 | `call` volta a devolver `nil` (o estado de antes da junta) | **7 de 10** exemplos vermelhos: `expected nil.present? to be truthy`. Os 3 que sobrevivem são **exatamente os negativos** — a prova de que eles passavam no vácuo |
| 2 | derivar o Google Ads do `google_ads_send_to` | `expected ["123456789", "AbC-D_efGh12", "a", nil] to all be nil` e `google_ads_ready?` → `expected false, got true` |
| 3 | `find_by(account_id:)` sem a inbox — o contrato "por conta" | `a credencial de uma inbox nao vale para outra da mesma conta`: `expected: nil` |
| 4 | pôr a URL chamada na mensagem de erro e logá-la ("melhorar o diagnóstico") | DLQ: `not to include "EAAtoken-da-junta-..."` **falha**; log: idem. O token viaja na query da CAPI, e a query entrou nos dois |

O arquivo emprestado da prova 4 (`destinations/base.rb`, de outra trilha) foi restaurado com `git
checkout --` e está idêntico ao `HEAD`.

### 2.2 Cada afirmação de ausência tem um controle ao lado

- *"sem credencial não entrega"* vem **em par** com *"o mesmo cenário com credencial entrega"* — só
  muda a linha do cofre;
- *"o segredo não está na DLQ"* vem depois de `expect(...[:query][:access_token]).to eq(meta_token)`
  — o segredo **realmente viajou** naquela requisição;
- *"o log não tem o segredo"* vem depois de `expect(saida.string).to include('Tracking::MetaCapiDeliveryJob', entrega.id.to_s)`
  — o logger **realmente capturou** o trabalho daquela entrega;
- *"não vazou e-mail nem telefone"* vem depois de `expect(entrega.suppressed_field_names).to include('em', 'ph')`
  — a base **tinha** os dois e os reteve. O contato do spec nasce com e-mail e telefone por isso.

### 2.3 Um controle que acusou um fato

`expect(entrega.field_names).to be_present` na entrega **morta** ficou vermelho: `field_names` só é
gravado no caminho de sucesso (`apply`), enquanto `mark_dead` grava status, HTTP e motivo. Não é
defeito — é o desenho — mas a asserção estava medindo zero onde eu a tinha posto. Movi a prova do
log de auditoria para a entrega **bem sucedida**, que é a única que grava a lista.

### 2.4 A captura de log olha os dois loggers

`ActiveJob::Base.logger` **e** `Rails.logger`. Um `Rails.logger.error` posto no meio de um destino
escaparia de uma captura que só olhasse o primeiro — foi o que a prova 4 mostrou.

---

## 3. O que ficou de fora, e por quê — **precisa de dono**

### 3.1 Google Ads server-side continua inerte: **duas** dependências externas, não uma

1. **`google_ads_access_token`** — o cofre guarda o **refresh** token (`google_ads_refresh_token`) e
   o `oauth_metadata`. Trocar um pelo outro é o OAuth de um clique, a **metade (b) do 5.02**, que o
   relatório daquela trilha já declarou não feita: exige app registrado no Google Cloud com consent
   screen publicado e **developer token do Google Ads aprovado**. Cadastro do dono, não código.

2. **`google_ads_customer_id` e `google_ads_conversion_action_id` não têm onde morar** — e isto
   **não** estava registrado em lugar nenhum. Não existem no cofre nem no `widget_tracking`, e
   **não são deriváveis do `google_ads_send_to`**: o `AW-000/Rótulo` do gtag é o id da *tag* de
   conversão com um rótulo opaco, enquanto a API quer `customers/<CID>/conversionActions/<ID>` —
   dois números diferentes desses dois. Derivar produziria payload rejeitado e entrega morta na DLQ
   que ninguém consegue explicar. `google_ads_login_customer_id` só faz sentido com conta MCC e
   chega junto do OAuth.

**Consequência:** quando o OAuth do 5.02(b) chegar, ele ainda **não basta**. Alguém precisa decidir
onde `customer_id` e `conversion_action_id` são gravados — colunas novas no cofre (não são segredo,
mas são do Ads) ou chaves novas no `widget_tracking`. Há spec travando a fronteira: o dia em que
alguém ligar o Google Ads pela metade, ele fica vermelho **antes** de a frota descobrir pela DLQ.

### 3.2 O modo com PII continua desligado

`Tracking::PiiPolicy::DPA_SIGNED` segue `false`, e há exemplo afirmando isso ao lado da prova de que
o corpo entregue não leva `em`/`ph`/`fn`/`ln` de um contato que os tem. Depende da **verificação 2**
(jurídico), que não existe. Nada aqui a destravou.

### 3.3 Dois comentários que agora mentem — **em arquivos que não são meus**

Ligar o resolver deixou duas afirmações desatualizadas:

- `app/services/tracking/event_recorder.rb:38` — *"é segura de ligar HOJE porque
  `Tracking::CredentialResolver` ainda devolve `nil` (o bloco 5.02 não aterrissou)"*;
- `app/services/tracking/delivery_dispatcher.rb:10` — *"Sem credencial (o estado de hoje, enquanto o
  bloco 5.02 não aterrissa) nada acontece"*.

Nenhum muda comportamento — é comentário puro, três linhas cada. Perguntei ao coordenador se podia
corrigi-los; o `ask` expirou em 10 min sem resposta, então **não toquei**, pela regra de propriedade
de arquivo. Fica para a trilha dona ou para uma autorização explícita.

---

## 4. Como rodei, e os números

```
cp /home/chatwoot/chatwoot/.env .                        # worktree nao tem .env
export POSTGRES_DATABASE=chatwoot_test_spx_junta         # banco dedicado, nao o compartilhado
RAILS_ENV=test bundle exec rails db:create db:schema:load
```

| Comando | Resultado |
|---|---|
| `rspec spec/services/tracking/credential_resolver_spec.rb spec/jobs/tracking/delivery_with_stored_credential_spec.rb` | **23 examples, 0 failures** |
| `rspec spec/services/tracking spec/jobs/tracking spec/models/tracking_*_spec.rb spec/services/tracking_credentials` | **228 examples, 0 failures** |
| `rspec spec/controllers/.../tracking_credentials_controller_spec.rb` (regressão do 5.02) | **15 examples, 0 failures** |
| `rubocop` nos 3 arquivos tocados | **no offenses detected** |

`N > 0` em todos — a contagem está acima, não é "sem falhas" com zero exemplos. Pré-requisito 0.10
conferido e não presumido: `Chatwoot.encryption_configured?` → `true`.

---

## 5. Arquivos

| Arquivo | O quê |
|---|---|
| `app/services/tracking/credential_resolver.rb` | a junta: lê o cofre por inbox e o `widget_tracking` da inbox |
| `spec/services/tracking/credential_resolver_spec.rb` | 13 exemplos — as duas metades, a âncora, o escopo por inbox, a fronteira do Ads |
| `spec/jobs/tracking/delivery_with_stored_credential_spec.rb` | 10 exemplos — ponta a ponta, sem dublar o resolver |

Nenhum arquivo de outra trilha ficou modificado (`git status` limpo fora destes três).
