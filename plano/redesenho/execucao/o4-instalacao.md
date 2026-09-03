# Onda 4 · Instalação por plataforma (5.22) e contexto externo (5.23)

**Trilha:** `o4-resto` · **Commits:** `1bf8b3fb79` e `758f8d6111` (locais, não pushados — congelamento da integra) · 19/08/2026

| Bloco | Estado |
|---|---|
| **5.22** — WordPress, Wix e GTM | **entregue** |
| **5.23** — contexto do sistema externo ao lado da conversa | **entregue** (`758f8d6111`) |

---

## 1. 5.22 — o documento, e o que ele não é

**`docs/tracking/instalacao-por-plataforma.md`.** A §1 do guia do 5.15 ensina a instalação genérica
("copie o trecho e cole antes do `</body>`"). Este documento responde **onde exatamente**, em cada
plataforma — e, em cada uma, **a armadilha que faz a instalação parecer certa e não funcionar**.

O aceite herdado do 5.15 é *"uma pessoa que nunca viu o produto instala seguindo só o documento"*.
Por isso o critério aqui não foi "o documento existe", e sim **um caminho que funciona sem
conhecimento prévio** — incluindo o passo que todo mundo esquece (publicar) e o sintoma de cada erro.

| Plataforma | A armadilha, e por que ela morde |
|---|---|
| **WordPress** | Editar `footer.php` pelo editor de tema é o que todo tutorial ensina — e a **próxima atualização do tema apaga**. O chat some do site semanas depois, sem ninguém ter mexido. Caminho certo: plugin de inserção de código (fica no banco) ou tema filho. Segunda armadilha, com receita própria: plugin de cache adiando/minificando o JS — o sintoma é o chat aparecer **para o admin logado** e não para o visitante |
| **Wix** | Código personalizado **exige plano pago**, e não há caminho alternativo: o app de HTML embutido roda em **iframe isolado**, onde o chat ficaria preso a um retângulo em vez de flutuar. Está na primeira linha da seção, porque descobrir isso no fim custa a tarde de quem tentou. E o Wix **não executa** código personalizado na prévia — só no site publicado |
| **GTM** | Tag de **HTML personalizado**, nunca template de galeria: templates rodam em *sandboxed JavaScript*, sem `document` e sem closures livres, e o carregador precisa das duas coisas. Um template exigiria reescrever o SDK para a sandbox e submetê-lo à aprovação |

**O documento não cola uma cópia do trecho** — ele manda copiar do painel. Há spec que reprova se
alguém colar: trecho copiado envelhece na primeira mudança do carregador, e o integrador cola a
versão velha, que é pior que não ter documento.

**Nada de JavaScript em string de tradução.** As duas chaves i18n novas são prosa; o
`noExecutableJs.spec.js` (que varre os 57 idiomas) continua verde.

## 2. A regra R9, verificada nas duas metades

O aceite diz: *"o snippet do GTM não sobrescreve `window.dataLayer` do cliente"*. Isso tem duas
metades, e só uma se verifica lendo texto:

1. **o trecho que o servidor gera** — `instalacaoPorPlataforma.spec.js` lê `web_widget.rb` e exige
   que ele não escreva em `dataLayer` nem em `gtag`. Ele só baixa o `sdk.js`;
2. **o SDK que o trecho carrega** — `sdk/specs/browser/gtm-datalayer.check.mjs` carrega o `sdk.js`
   **construído** sobre um `dataLayer` que já existe e verifica preservação por **identidade**
   (`===`), que é a diferença entre estender e substituir e é o que um mock não consegue perder.

**E a garantia que faz o integrador confiar em chamar o SDK de dentro de uma tag:** no contêiner, as
tags de um acionamento rodam **em sequência, no mesmo contexto**, e uma exceção síncrona interrompe
as **seguintes** — o site continua no ar e para de medir, com a culpa caindo no chat. O check simula
três tags, com a do meio chamando o SDK com argumento inválido, e exige que a terceira rode. O
documento explica a garantia e mostra o `.catch()` para quem quiser tratar.

## 3. ACHADO GRAVE — `setConsent` nunca funcionou, e o defeito é meu (5.09)

`setConsent` e `updateConsent` passavam `undefined` como validador para `chamadaDeDados`, que chamava
`validar()` sem guarda. O `TypeError` caía no `try`, virava `Promise.reject`, e
`enfileirar(despachar, …)` **nunca era chamado**.

**Medido em navegador antes de corrigir:** `setConsent({ analytics_storage: 'granted' })` deixava os
quatro propósitos em `denied` e o `dataLayer` sem nenhuma entrada de `consent`.

O efeito no cliente é o pior possível para o bloco: **um site com CMP que ACEITA cookies ficava com a
medição inteira desligada** — o inverso exato do que o 5.09 protege — e em silêncio, porque a
rejeição só aparece no console. Introduzido em `c6964e5345`.

**Correção:** `validar?.()`. Cobertura nova: `sdk/specs/consentApi.spec.js` (4 exemplos, pela API
pública, com a fila pré-boot drenada) mais uma asserção no check de navegador. Sabotagem confirma que
os dois pegam a regressão.

**Ponto declarado, não corrigido:** `setConsent` passa pela **fila pré-boot**, então o `default` do
Consent Mode só é publicado quando o painel carrega. O Consent Mode v2 pede que o `default` saia
**antes de qualquer tag** — o próprio `consent.js` diz isso no cabeçalho. Enfileirar o consentimento
contraria o motivo de ele existir. É decisão de arquitetura do 5.09, não desta trilha: **escalado**.

## 4. O ponto cego que a sabotagem achou

A primeira versão do `gtm-datalayer.check.mjs` passava **verde** com `window.dataLayer = []` plantado
no `consent.js` — porque nada no boot chega a publicar no `dataLayer`. Um verificador que não
exercita o caminho perigoso não protege dele. Está escrito no arquivo, junto com o que o cobre de
fato (`ponte-de-tags.check.mjs`, onde essa sabotagem derruba 6 asserções).

## 5. Verificação

| | Resultado |
|---|---|
| `instalacaoPorPlataforma.spec.js` (novo) | 10 exemplos |
| `guiaDeIntegracao.spec.js` + specs da tela de tracking | 60 exemplos, 0 falhas |
| `gtm-datalayer.check.mjs` (Chromium real, artefato construído) | **9 asserções, 0 falhas** |
| `consentApi.spec.js` (novo) | 4 exemplos |
| eslint | limpo |

## 6. 5.23 — "Recebido do site"

**Entregue** (`758f8d6111`). `SiteContext.vue` + `helper/originAttributes.js`, ligados no
`ContactPanel` como item próprio da barra lateral.

### 6.1 O que a seção mostra, e por que nessa ordem

Três blocos, e a divisão espelha onde o servidor grava (`Tracking::OriginRecorder`), não uma
escolha visual: **de onde veio esta pessoa** (o `first_*` do contato), **o que trouxe esta
conversa** (o `last_*` da conversa) e **identidade**. Um selo, uma vez, no topo — aqui dentro
tudo veio do site, então repeti-lo por linha seria ruído. É o oposto da seção do 1.17, onde os
atributos do site convivem com os do agente na mesma lista e o selo precisa ser por item.

**Nenhum request novo**, que é aceite: `custom_attributes` já vem no payload do contato e da
conversa, e os **rótulos** saem das `CustomAttributeDefinition` que a store de atributos já
carregou — já traduzidos pelo servidor (`tracking_origin.*.yml`, bloco 1.18). O front não ganha
uma segunda tabela de rótulos, então não há como os dois nomes divergirem. Sem definição
carregada, o rótulo é a **chave crua** — nunca uma tradução inventada aqui, que divergiria da que
o servidor escolheu.

### 6.2 As três regras que o 1.19 impôs, e como cada uma ficou

| Regra | Como ficou |
|---|---|
| **ausência tem nome** | `origin_kind` com `nao_disponivel` **aparece**, traduzido como "Não disponível". Se a linha sumisse, o painel ficaria calado — e silêncio, para quem lê, é indistinguível de "veio direto", que é a mentira que o 1.22 proibiu |
| **não fingir dado** | chave sem valor não vira linha; `origin_kind` **desconhecido** sai cru em vez de sumir. Valor estranho na tela é bug visível; linha que some é bug que ninguém abre |
| **seção vazia não aparece** | com zero linhas em tudo, o componente não renderiza e o accordion some junto |

### 6.3 O que o site mandou × o que o agente digitou

A seção **não varre por prefixo**. `last_contato`, criado por um agente, tem o prefixo de origem
e **não** é chave de origem — entraria sob o selo "recebido do site" e mentiria sobre quem
escreveu o quê, justamente o que a seção existe para evitar. A lista canônica é
`Tracking::OriginAttributes`; `helper/originAttributes.js` a espelha e um spec **lê o arquivo
Ruby** e reprova se as duas divergirem (9 exemplos).

### 6.4 A armadilha do 1.17, medida — e o resultado surpreende

O aviso era: *conferir que o que você lê é o que a store escreve*. Conferi passando o payload
pela **mutation real** (`siteContextStoreShape.spec.js`), não lendo o código — foi lendo o código
que o "Endereço IP" se perdeu, com 30 testes verdes.

**`stopPaths: ['custom_attributes']` protege o CONTEÚDO, não a chave do topo.** O registro guarda
`contato.customAttributes.first_utm_source`: **camelizado por fora, snake_case por dentro**. Quem
lê só o `stopPaths` conclui o contrário — eu concluí, e o teste me corrigiu.

A seção aceita as duas formas, então não depende de como o defeito irmão (§6.6) for resolvido. E
a contraprova está no mesmo arquivo: `additional_attributes` **é** camelizado por inteiro. Ter as
duas asserções lado a lado deixa a diferença impossível de ler errado.

### 6.5 Posição na barra — o item novo quase nasceu invisível

O `else` genérico da reconciliação de `useUISettings` empurra item novo para o **fim** da lista.
Para quem já usa o produto — quase todo mundo, porque a ordem salva existe desde a primeira vez
que alguém arrastou um item — o fim da lista é o mesmo que não existir, e o aceite é responder
**sem rolar a barra inteira**. Ganhou caso próprio (como `conversation_media` e
`group_participants` já tinham): entra **colado em `contact_attributes`**, que é a lista que ela
contextualiza. Três exemplos guardam isso.

### 6.6 ESCALADO — os valores dos atributos de contato NÃO renderizam *(confirmado)*

Achado enquanto media a §6.4, **não corrigido**, e é do 1.17/upstream:

`CustomAttributes.vue:65` faz `return contact.value.custom_attributes || {}` para
`attributeType === 'contact_attribute'`. O `contact` vem de `getters['contacts/getContact']`, que
devolve o registro **da store** — e a store guarda `customAttributes`. Logo, `custom_attributes` é
`undefined` e o componente cai no `|| {}`.

Efeito deduzido: a lista de atributos de contato é montada a partir das **definições**, então os
rótulos aparecem; o **valor** de cada um sairia vazio. O escopo `conversation_attribute` não é
afetado — a store de conversas não cameliza.

**CONFIRMADO** pelo coordenador do merge, executando o `camelcaseKeys` real com o payload real —
não pela tela, e isso é melhor: a tela prova que está vazio *naquele contato*; executar o módulo
prova *por quê*, e para todo contato. Saída dele:

```
chaves de topo:         id, customAttributes, additionalAttributes
r.custom_attributes:    undefined
r.customAttributes:     {"first_utm_source":"google"}   <- conteúdo protegido, chave camelizada
r.additionalAttributes: {"browserLanguage":"pt"}        <- contraprova
```

Com `custom_attributes` em `undefined`, a linha 78 (`attribute.attribute_key in
customAttributes.value`) é **sempre falsa**: rótulo aparece, valor sai vazio.

**Há precedente, e ele confirma o diagnóstico:** `ComposeNewConversationForm.vue:158` já faz
`contact.customAttributes || contact.custom_attributes || {}`. Alguém pisou nisso antes e
consertou **pontualmente**, sem varrer os outros consumidores.

**Varri os outros consumidores, e a lista está fechada** — só `CustomAttributes.vue:65` está
errado. Os que pareciam suspeitos não são:

| Consumidor | Veredito |
|---|---|
| `MessageList.vue:197` | lê de `chat.meta?.sender`, que vem do payload da **conversa** — não camelizado. Correto |
| `currentAccount.custom_attributes` (billing, onboarding) | a store de accounts **não** cameliza. Correto |
| `ContactCustomAttributes.vue`, `ContactsCard`, `ContactDetails`, `ContactsList` | já leem `customAttributes`. Correto |

Conserto: uma linha, do mesmo formato que o 1.17 aplicou ao IP —
`contact.value.customAttributes || contact.value.custom_attributes || {}`. Está na fila de
commits pós-merge do coordenador, registrado.

### 6.7 Verificação

| | Resultado |
|---|---|
| `SiteContext.spec.js` | 17 exemplos |
| `originAttributes.spec.js` (cruza o Ruby) | 9 exemplos |
| `siteContextStoreShape.spec.js` (mutation real) | 5 exemplos |
| `useUISettings.spec.js` (posição na barra) | +3 exemplos |
| **`site-context-contrast.check.mjs` (Chromium, CSS real, 2 temas)** | **8 asserções** |
| suíte do dashboard tocado | 1.479 exemplos, 0 falhas |

O check de contraste existe porque **o selo do 1.17 reprovou com 4,14** (mínimo AA é 4,5) e este é
uma combinação nova (`text-n-slate-12` sobre `bg-n-slate-3`), então herda o risco inteiro. Medido
com Tailwind + skin + next-colors compilados: **15,57 no claro e 12,13 no escuro**; títulos 17,46 e
14,82. As classes saem do componente por regex — copiá-las mediria uma fixture, que seguiria verde
depois de alguém trocar a cor. Sabotagem com `text-n-slate-9` derruba para **2,72**, nos dois temas.

### 6.8 O que ficou de fora, declarado

**O lead incompleto (4.18) não entrou.** Ele existe no servidor (`WidgetPartialLead`, com rotas e
relatório próprios) mas **não chega ao payload da conversa** — exibi-lo exigiria uma requisição
nova, e o aceite do bloco diz, com todas as letras, que nenhuma informação nova é buscada por
request extra. Entre furar o aceite e deixar o dado de fora, deixei de fora e escrevi aqui. Quando
alguém decidir publicá-lo no payload (é o lugar natural: ele já é do mesmo `contact_inbox`), a
seção ganha um quarto bloco sem mudar de forma.

**O app embutido continua adiado**, como o próprio bloco previa: `ConversationBox.vue` monta abas
de dashboard apps por `v-for`, então adiar não custa arquitetura — custa só a decisão de quando.
