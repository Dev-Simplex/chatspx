# Integração das ondas — branch `redesenho-integra`

**Data:** 18/08/2026 · **Autor:** o coordenador · **Base:** `c06ba1824e` (fim da Onda 0)

## 1. O que entrou

| Trilha | Branch | Blocos | Merge |
|---|---|---|---|
| Widget | `o1-widget` | 1.01 – 1.08 | limpo |
| Bridge | `o1-bridge` | 1.09 | **conflito — resolvido por união (§2)** |
| Backend | `o1-backend` | 1.11, 1.12, 1.13 | limpo |
| Origem | `o1-origem` | 1.20 | limpo |
| Pré-chat | `o2-config-prechat` | 3.12, 3.13 | limpo |
| Telas | `o2-config-telas` | 3.06 | limpo |
| Complementar | `o2-config-resto` | 3.05 | limpo |

**Régua na branch integrada: `vitest` — 4.775 testes, 0 falhas, exit 0.**
(A linha de base da Onda 0 eram 4.619. Os 156 a mais são das ondas.)

## 2. O único conflito, e por que a resolução importa mais que o conflito

`app/javascript/sdk/specs/IFrameHelper.spec.js` — **add/add**. Duas trilhas criaram o mesmo
arquivo, sem saber uma da outra, com conteúdos **disjuntos**:

- **widget (1.03)** — 9 testes de `applyWidgetTokens`: os 7 tokens do servidor atravessam o
  `postMessage` e são escritos no elemento, token a token.
- **bridge (1.09)** — 7 testes de `isTrustedFrameOrigin` / `onPostMessage` /
  `initPostMessageCommunication`: a origem da mensagem é conferida e o `window.onmessage` do site
  não é sequestrado.

**Resolvido por união: 16 `it(` no arquivo integrado.** Escolher um lado — que é o que um
`-X ours` ou um `-X theirs` faria — teria apagado 7 ou 9 asserções **em silêncio**, e o arquivo
continuaria compilando e passando verde. É a forma mais limpa de perder teste que existe: nada
falha, nada avisa, e a cobertura some.

O arquivo integrado carrega um cabeçalho explicando a história e dizendo que, **se conflitar de
novo, a resolução correta continua sendo união**. Sem esse parágrafo, o próximo a resolver esse
conflito escolhe um lado e ninguém percebe.

> Sobre o import: o lado do bridge contava com os globais do vitest e o do widget importava
> explicitamente. Unifiquei no import explícito, acrescentando o `afterEach` que só o bridge usa.

## 3. O que a integração destravou — e é o motivo dela ter sido feita agora

Três trilhas novas nasceram **sobre a branch integrada**, e não sobre a base da Onda 0. Isso muda
o que elas conseguem fazer no primeiro minuto:

| Trilha nova | Blocos | Dependência satisfeita pela integração |
|---|---|---|
| `o5-primitivos` | 2.01, 2.02, 2.03, 2.04, 2.12 | 2.01 ← **1.01** ✅ → começa destravada, e a cadeia restante é interna |
| `o5-movimento` | 2.10, 2.13, 2.14, 2.17 (+2.08, 2.18 bloqueados) | 2.10 ← 1.01 ✅ · 2.13 ← 1.09 ✅ · 2.14 ← 1.05 ✅ · 2.17 ← sem dep |
| `o3-flows-captura` | 4.01, 4.02 (+4.03 bloqueado) | 4.01 ← 0.2 ✅ |

E destravou a trilha de **pré-chat**, que estava parada no 3.14 por falta do `useInboxWidgetConfig`
e do `widgetConfigFields.js` — ambos do 3.06, ambos agora na base. Ela mergeou por conta própria,
no momento que escolheu.

## 4. Uma fronteira que precisou de arbitragem

O 3.14 precisa de dois descritores (`pre_chat_form_enabled`, `pre_chat_form_options`) num arquivo
que é território da trilha de **telas**. Decidi: **o arquivo é deles, a semântica do pré-chat é da
trilha de pré-chat** — quem escreve os dois descritores é quem conhece o que eles significam.
Avisei as duas pontas para nenhuma escrever o mesmo par, e exigi acréscimo **aditivo e mínimo**,
para que um conflito eventual saia por união e custe barato.

A trilha de telas confirmou e devolveu a nota que faltava no contrato: `group: true` (contagem por
subcampo) hoje vale **só** para as 4 chaves de `additional_attributes`; `pre_chat_form_options`
viaja inteiro, sem `group`. Ou seja, editar qualquer subcampo do pré-chat conta como **uma**
alteração não salva, não como N. Repassei à outra ponta antes que ela escrevesse.

> Por que essa insistência: o pior defeito desta execução foi de **junção**, não de arquivo — o
> upstream passou a filtrar um campo na leitura, o formulário continuou reenviando o objeto
> inteiro, e abrir "Editar" numa integração **apagava a credencial do cliente**. Os dois lados
> pareciam certos isolados, e por isso passou por 100 % dos testes verdes.
