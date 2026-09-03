# Bloco 4.22 — coexistência com as campanhas legadas · relatório

Worktree: `/home/chatwoot/chatwoot-o2-config-resto` · branch `o6-ia` · autor único.
Base mergeada no início: `redesenho-integra` (`58e308b356`).

---

## 1. A REGRA DE PRECEDÊNCIA, chave por chave

Era o que o coordenador pediu explícito. Ela lê **uma** chave: `widgetTriggers.enabled`,
em `inbox.additional_attributes` e publicada no payload de boot.

| Estado da conta | Abordagem nova (teaser/auto-open) | Campanha legada |
|---|---|---|
| `widget_triggers` ausente | não roda | **dispara**, exatamente como hoje |
| `enabled` ausente | não roda | **dispara** |
| `enabled: false` | não roda | **dispara** |
| `enabled: true` | roda | **não dispara sozinha** — continua listada, editável e válida |

`enabled` só liga com o booleano `true`. `'true'` (string) e `1` **não** ligam — é o mesmo
contrato que o 4.04 fixou para o SDK, e o motivo é a frota: ausência ou lixo não pode ligar
comportamento novo em conta nenhuma.

### 1.1 A pergunta do visitante: e quando ele já dispensou um dos dois?

**Dispensa do teaser (`cw_teaser_dismissed`) e degradação por familiaridade (`cw_approach`,
bloco 4.19) NÃO devolvem a vez à campanha legada.**

A decisão é de **conta**, não de visitante — e isso é escolha, não esquecimento:

- os dois estados significam *"o produto decidiu poupar ESTE visitante"*;
- se a campanha legada disparasse ali, quem dispensou o convite receberia **outro convite
  por outra porta**, e quem caiu da escada de familiaridade voltaria ao topo por fora. A
  degradação do 4.19 viraria enfeite — que é exatamente o risco que o coordenador nomeou.

**Consequência aceita, escrita para não virar surpresa:** um visitante que dispensou o
teaser não vê mensagem proativa nenhuma naquela sessão. É o objetivo do desenho, não efeito
colateral dele.

O predicado não recebe estado de visitante — e há um exemplo que asserta a própria aridade
da função, para que acrescentar esse estado depois exija mexer no teste e ler este parágrafo.

### 1.2 Como isso convive com o 4.05, sem contradizê-lo

O 4.05 vinculou teaser ↔ campanha com *"campanha é mensagem, gatilho é momento"*. A regra
daqui **não** o contradiz porque a supressão é do **DISPARO**, nunca do registro:

- a campanha continua no store, na lista e na tela de edição;
- ela continua sendo a **mensagem** do convite;
- o que ela deixa de fazer é **agendar o próprio disparo**.

Apagar ou desativar a campanha ao ligar o gatilho apagaria o texto que o cliente escreve na
tela do teaser. Por isso a única desativação que existe neste bloco é a **explícita**, feita
pelo cliente ao importar (§3).

---

## 2. Uma fonte, dois lados do iframe

O defeito que este bloco existe para não ter não era uma regra errada: era **a mesma regra
escrita em dois lugares**, livre para divergir.

- a condição que **monta** a abordagem vive no host (`IFrameHelper.montarTeaserSeConfigurado`);
- a condição que **suprime** a campanha vive dentro do iframe (`widget/store/modules/campaign.js`).

Se a supressão for mais **larga** que a montagem, a conta perde a mensagem proativa que tinha
e ninguém aparece no lugar. Se for mais **estreita**, o visitante leva as duas. Nos dois casos
cada lado está "certo" sozinho.

**Correção:** `app/javascript/shared/helpers/abordagemProativa.js`, importado pelos dois. O
`IFrameHelper` trocou o `gatilhos.enabled !== true` inline pela função — comportamento
idêntico, sem segunda cópia.

**Guarda contra a reincidência:** há exemplo que lê os dois arquivos-fonte e falha se alguém
reescrever a comparação na mão em qualquer um dos lados. É assim que a divergência voltaria.

### 2.1 O detalhe do relógio, que só aparece em site de página única

A supressão chama `campaignTimer.initTimers({ campaigns: [] })` em vez de um `return` seco.
O `initTimers` **começa limpando** os relógios já armados; um `return` deixaria vivo um
relógio de navegação anterior, e o visitante levaria a campanha **uma URL depois**. Há
exemplo nomeando isso.

### 2.2 Contrato (cicatriz nº 6)

| Item | Valor |
|---|---|
| Chave lida | `chatwootWebChannel.widgetTriggers.enabled` |
| Tipo | booleano estrito |
| Default / ausência | tratado como `false` → campanha legada dispara |
| Quem escreve | `inbox.additional_attributes['widget_triggers']`, schema em `WidgetTriggersSchema` |
| Quem lê | host (`sdk/IFrameHelper.js`) e iframe (`widget/store/modules/campaign.js`), **pela mesma função** |
| Superfície nova | nenhuma chave nova, nenhuma migration, nenhum campo novo na ponte |

---

## 3. A rampa: importar a campanha como gatilho

`POST /api/v1/accounts/:account_id/campaigns/:display_id/import_to_trigger`

**As duas metades numa transação**, que é o aceite: cria o gatilho equivalente **e** desativa
a campanha, juntas ou nenhuma. Se a escrita do gatilho falhasse depois de a campanha ser
desativada, o cliente ficaria sem mensagem proativa nenhuma e sem saber por quê; se a campanha
continuasse ligada depois de o gatilho nascer, o visitante teria dois convites. Há exemplo
para o meio do caminho.

### 3.1 O que "equivalente" quer dizer, campo a campo

| Campanha legada | Gatilho novo | Por quê |
|---|---|---|
| `trigger_rules.time_on_page` | gatilho `time_on_page`, ligado em **desktop e mobile** com o mesmo valor | a campanha nunca distinguiu plataforma; inventar a distinção na importação mudaria o comportamento sem o cliente pedir |
| `trigger_rules.url` | `audience.url` com operador **`contains`** | a campanha legada casa por inclusão (`campaign.rb:143-145`); `equals` deixaria de disparar em páginas que hoje disparam — regressão silenciosa dentro da própria migração |
| `message` / `title` | **não é copiado** | pelo 4.05 a mensagem **é** a campanha vinculada; copiar criaria a segunda cópia que aquele bloco existe para não ter, e o schema recusaria a chave (`additionalProperties: false`) |

Bordas resolvidas e testadas: tempo ausente vira `0` (imediatamente); tempo acima do teto do
schema é **cortado em 86.400** em vez de derrubar a importação com um 422 que o cliente não
sabe consertar; importar a **segunda** campanha preserva o que já existia e **substitui** o
gatilho de mesmo id em vez de criar um duplicado; o resultado é validado contra
`WidgetTriggersSchema::SCHEMA` dentro do próprio spec.

### 3.2 A seção "modo antigo" na tela

Fica **depois** do convite, de propósito: a ordem da tela conta a precedência — o que fala com
o visitante vem primeiro, o que está em rampa vem embaixo.

O **aviso é o produto** desta seção, e ele muda com o estado: com o gatilho ligado, diz que as
campanhas não disparam sozinhas e que desligar o gatilho as traz de volta **sem republicar
nada**; com o gatilho desligado, diz que continuam disparando normalmente. Uma seção que só
listasse campanhas seria pior que nenhuma — mostraria "ativa" ao lado de algo que não dispara.

Só as campanhas **ligadas** desta inbox aparecem: a importada sai da lista sozinha, e é assim
que o cliente vê o progresso da migração.

---

## 4. Os quatro aceites

| Aceite (§2.2) | Onde está verificado |
|---|---|
| Conta com campanha legada **e** gatilho ativo: o visitante vê **uma** mensagem proativa, e é a do gatilho | `suppression.spec.js` — `initTimers` recebe lista vazia |
| Desligando o gatilho, a campanha volta a aparecer **sem republicar nada** | mesmo arquivo: o payload de boot muda e nada mais; nenhuma campanha é editada no meio |
| Conta que **só** tem campanha legada não muda de comportamento | mesmo arquivo, 2 exemplos — são a guarda contra suprimir demais, e passam com e sem a mudança de propósito |
| Importar cria o gatilho equivalente e **desativa** a campanha, nunca as duas ligadas | `campaign_import_service_spec.rb` + `campaign_import_to_trigger_spec.rb` |

---

## 5. Vermelho medido, restaurando o código antigo

| Sabotagem | Caem |
|---|---|
| a supressão sai do store (volta a competir) | **3 de 7** — inclusive "o visitante vê uma mensagem só" |
| importar deixa a campanha ligada | **3 de 19** — inclusive "nunca deixa as duas ligadas" |

O dublê da API entrou no spec do store porque, sem ele, o vermelho do `startCampaign` vinha de
um **404 de rede** — provaria a ausência do servidor, não a da regra.

---

## 6. Dois enganos meus que os testes pegaram

Registro porque os dois teriam produzido teste que mede o próprio engano:

1. **A rota resolve por `display_id`, não por `id`** (`campaigns_controller.rb:64`). Pedir pelo
   `id` devolve 404 — e um teste que aceitasse 404 como "isolamento funcionando" estaria verde
   sobre nada.
2. **`display_id` é sequencial POR CONTA.** O teste de isolamento entre contas, escrito de forma
   ingênua, pedia display_id `1`, o controller achava a **minha** campanha e devolvia 200. O
   exemplo só mede o que promete depois de a conta alheia receber três campanhas, para que o
   display_id procurado não exista na minha.

---

## 6.1 O aceite de aparência, medido em Chromium

Os 10 testes de unidade da seção rodam em jsdom, que não resolve cascata nem custom
property — ele confirma que a classe está lá, nunca que a cor chegou. O aceite de aparência
foi medido no navegador (`spec/e2e/dashboard/modo-antigo/`, Vite em porta **efêmera**, sem
encostar no harness de porta fixa, que serve o widget e é de outra fila).

```
MEDIDO NO CHROMIUM (6 passed):
  [claro]  aviso rgb(0, 108, 85)    sobre rgb(212, 242, 234) = 5,40:1
  [escuro] aviso rgb(134, 240, 188) sobre rgb(8, 61, 49)     = 8,83:1
  [claro]/[escuro] nome acessível = "Importar a campanha Convite dos planos como gatilho"
  [claro]/[escuro] transbordo em 900 px = 0 px
```

Os dois passam o AA de texto pequeno (4,5:1). **A primeira versão não passava** — ver §7.3,
que é o achado desta medição.

O nome acessível vem da árvore do **próprio Chromium**, por CDP — não de
`getByRole({ name })`, que calcularia o nome com a implementação do Playwright. O que precisa
ser provado é o que o **navegador** computou, porque é isso que o leitor de tela lê. O emoji
que o cliente pôs no título da campanha fica na tela e **sai** do nome.

Transbordo medido por `getBoundingClientRect`, nunca por `scrollWidth`: em elemento com
`overflow: visible` o `scrollWidth` devolve a largura da caixa e o teste jamais falharia.

---

## 7. Achados que NÃO são meus, roteados

### 7.1 O guarda `teaserEnabled` do 4.06 está morto

`sdk/teaser.js:138` recusa montar quando `canal.teaserEnabled === false`. Mas o payload de boot
publica essa flag **aninhada**, em `chatwootWebChannel.profileConfig.teaserEnabled`
(`show.html.erb:65`, vinda de `WidgetProfile`), e **o SDK nunca lê `profileConfig`** — conferido
por varredura: zero ocorrências em `app/javascript/sdk/`.

Logo `canal.teaserEnabled` é sempre `undefined`, a comparação nunca é verdadeira e **o guarda
não guarda nada**. Efeito prático: uma conta no perfil **support** (onde `teaserEnabled` é
`false` por padrão) que ligue os gatilhos recebe o teaser assim mesmo.

**Como isso mudou o meu bloco:** eu ia usar `teaserEnabled` como segunda condição da supressão.
Não usei — minha regra espelha o que o teaser **de fato** faz hoje (`enabled === true`), e não o
que ele deveria fazer. Se o 4.06 consertar o guarda, a supressão precisa ganhar a mesma
condição, e o lugar é **um só** arquivo (`shared/helpers/abordagemProativa.js`).

### 7.2 O texto do teaser não é o da campanha vinculada

O 4.05 (`TeaserComposer.vue`) edita `title`/`message` da campanha de chat ao vivo da inbox,
sob o princípio "campanha é mensagem". Mas o teaser do 4.06 renderiza
`canal.welcomeTagline || canal.welcomeTitle` (`sdk/teaser.js`), e **a campanha não viaja no
payload de boot**. As duas pontas não se encontram.

Não toquei — é junção 4.05 ↔ 4.06. Mas ela **agrava** o efeito da minha regra: com o gatilho
ligado, a campanha para de disparar e o teaser mostra outro texto, então a mensagem que o
cliente escreveu no compositor não aparece em lugar nenhum. **Recomendo tratar antes de o 4.22
chegar a cliente.**

### 7.3 Duas das cinco cores do `Banner` reprovam o AA no tema claro

**Achado da medição em Chromium, e ele é maior que o meu bloco.** A primeira versão desta
seção usava `Banner color="amber"`. Medido no navegador:

```
  [claro]  amber  rgb(171, 100, 0)  sobre rgb(255, 247, 194) =  4,25:1   REPROVA (AA pede 4,5)
  [escuro] amber  rgb(255, 202, 22) sobre rgb(48, 32, 8)     = 10,26:1   passa
```

Conferindo os tokens do design system (`dashboard/assets/scss/_next-colors.scss`), o padrão do
`Banner` é texto `-11` sobre fundo `-3`, e no tema **claro**:

| Cor | Contraste (claro) | |
|---|---|---|
| `slate` — **o default do componente** | **4,14:1** | reprova |
| `amber` | **4,25:1** | reprova |
| `ruby` | 4,70:1 | passa |
| `teal` | 5,40:1 | passa |
| `blue` | 5,78:1 | passa |

Ou seja: **todo `Banner` do produto que use a cor padrão está abaixo do AA para texto pequeno
no tema claro** — não só o meu. Isso é do dono do design system, não deste bloco.

O que **eu** fiz: troquei a cor da minha seção para `teal` (suprimido) e `blue` (ainda
disparando), que passam. Não mexi no componente nem nos tokens — mudar `--slate-11` mexe em
toda a superfície do painel de uma vez.

Nota de leitura: neste fork o `blue` **é o verde da marca** (`--blue-3: 217 253 211`,
`--blue-11: 0 108 85`, iguais aos do `teal`). Não é defeito de token — é rebranding, e o nome
herdado do Radix deixou de descrever a cor. Conferi antes de escalar, para não reportar um
artefato do meu parsing como bug.

### 7.4 Lint pré-existente no `campaigns_controller`

`Metrics/CyclomaticComplexity` e `Metrics/PerceivedComplexity` em `campaign_stats` (linha 86) —
método que **não toquei** (meu diff é +10 linhas, nenhuma nele). O `rubocop` do hook reporta
sempre que o arquivo é inspecionado. Não acrescentei `rubocop:disable` no método de outro bloco;
deixo roteado.

---

## 8. Limites

- **Nenhuma migration.** A regra lê chave que já existe; a importação escreve em
  `additional_attributes`, que já existe.
- **Nenhum serviço externo** foi chamado. Nenhuma IA envolvida — este bloco não toca IA.
- **Não rodei a matriz de 20 snapshots do widget**: ela é do harness de porta fixa, que estava
  ocupado por outra trilha, e este bloco não muda pixel do widget (a supressão é de relógio, e
  a seção nova é do painel).
- Nada foi pushado, nenhum PR, nenhum deploy, nenhum restart.
