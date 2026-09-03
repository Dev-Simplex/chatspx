# BRIEFING DE EXECUÇÃO — Copiloto v2 (F0 + núcleo da F1)

> **Todo worker lê este arquivo antes da primeira linha de código.**
> Data: 2026-07-28 · VM 192.168.8.232 (homologação) · branch `homologacao`
> Aprovado pelo Walisson a partir do mockup: https://chatspx.app/mockups/copiloto-v2.html

---

## 1. O que estamos construindo

O **copiloto do agente** — o chat de IA que ajuda quem atende — ganha a experiência de um ChatGPT:
streaming token a token, thread persistida, parar/regenerar, e o visual monocromático da OpenAI.

**Fonte da verdade do design:** `public/mockups/copiloto-v2.html` (no repo). Abra o arquivo e leia o
CSS — os tokens `--oa-*` são o contrato visual. Não invente cor nem medida.

### Escopo desta rodada

| | |
|---|---|
| **F0** | corrigir o i18n do painel V2 e ligá-lo |
| **F1 (núcleo)** | streaming SSE, thread persistida, parar/regenerar, visual OpenAI |

**FORA de escopo:** aposentar respostas prontas (F2), tela própria (F3), matar o Copilot V1
(só depois que o V2 estiver validado em produção).

---

## 2. ZONA PROIBIDA — leia duas vezes

Palavras do Walisson:

> "o captain que to falando é o chat de copiloto que o agente tem, temos agentes de ia que criamos
> no sistema que ta um pouco interligado **não vamos mexer nisso**. tome cuidado."

**NÃO TOCAR:** `Captain::Assistant`, cenários, documentos/base de conhecimento, avaliação de
conversa, episódios, handoff, auto-resolve, `captain_*` (exceto o que for do copiloto).

A interligação é esta, e ela é **só leitura**:

```ruby
# enterprise/app/models/copilot_thread.rb:4
belongs_to :assistant, class_name: 'Captain::Assistant'
```

O copiloto **lê** o assistente (persona, conhecimento). **Nunca escreve nele.** Se a sua mudança
precisar escrever em tabela de agente de IA, PARE e use `ask` ao coordenador.

---

## 3. O bloqueio que você precisa conhecer

**A chave da OpenAI está revogada.** Verificado agora, direto na API:

```
chave global (.env)            → GET /v1/models → HTTP 401
chave da conta 3 (hook openai) → GET /v1/models → HTTP 401
```

Ou seja: **não dá para validar geração real de ponta a ponta nesta rodada.** Isso é esperado e não
é problema seu.

**Como trabalhar com isso:**
- construa tudo assumindo que a chave vai voltar;
- **teste com stub/mock do LLM** (specs) e com um emissor falso de tokens quando precisar ver a tela;
- o caminho de erro (401) tem que ficar **bonito e honesto** — hoje ele é justamente o estado mais
  provável de o agente encontrar. O mockup mostra como: mensagem clara, sem culpar a conexão do
  usuário, com botão de tentar de novo;
- **NÃO** coloque chave nova, não invente credencial, não commite segredo.

---

## 4. Contratos travados

### C1 — Endpoint de streaming (dono: A1; consumido por A4)

```
POST /api/v1/accounts/:account_id/copilot_threads/:thread_id/stream
Accept: text/event-stream
```

Eventos SSE (um `data:` por linha, JSON):

```
event: token   data: {"delta":"texto parcial"}
event: done    data: {"message_id":123,"finish_reason":"stop"}
event: error   data: {"code":"unauthorized","message":"..."}
```

Regras: cancelável pelo cliente (fechar a conexão aborta o job); `finish_reason` = `stop` |
`cancelled` | `error`; a mensagem final é persistida em `copilot_messages` **antes** do `done`.

### C2 — Tokens visuais (dono: A3; usados por A3 e A4)

Extraídos do mockup aprovado. **Copie os valores de `public/mockups/copiloto-v2.html`**, não os
reescreva de cabeça. Os principais:

```
claro:  bg #ffffff · texto #0d0d0d · secundário #5d5d5d · linha #e3e3e3
        bolha do usuário #f4f4f4 · hover #f0f0f0 · código #f7f7f8 · enviar #0d0d0d
escuro: bg #212121 · texto #ececec · secundário #b4b4b4 · linha #3a3a3a
        bolha do usuário #303030 · hover #2f2f2f · código #1a1a1a · enviar #ffffff
```

**Decisões estruturais que definem a aparência (não negocie):**
1. **A resposta da IA NÃO tem bolha** — é texto solto na coluna, sem avatar, sem etiqueta.
2. **Só a fala do usuário tem bolha**, cinza neutra, à direita, `border-radius:18px`.
3. **Nenhuma cor de destaque no fio do chat.** Preto, branco e cinza. Cor só na conversa do cliente.
4. **Composer em pill** (`border-radius:26px`) com botão de enviar circular escuro.
5. **Ações em ícones discretos** abaixo da resposta (copiar, refazer, 👍, 👎), 30x30.
6. Coluna de leitura ~65 caracteres na tela própria (não se aplica ao painel lateral, que é estreito).

⚠️ O painel atual usa `purple-600` **literal**. Isso sai: nada de cor de accent no chat.

### C3 — Onde o dado já existe

`copilot_threads` e `copilot_messages` já existem no schema. **Não crie tabela nova, não faça
migration.** Se concluir que é impossível sem migration, PARE e use `ask`.

---

## 5. Regras invioláveis

1. **Sem migration.** Nenhuma. Se precisar, pergunte antes.
2. **Não commite.** Working tree only — o coordenador revisa, testa e commita.
3. **Sem deploy, sem restart do serviço principal, sem `assets:precompile`.** O coordenador faz.
4. **Blindagem:** só esta VM. Zero SSH para .109 (Tozi PROD), .229, fábrica.
5. **Não dispare IA real contra conversa de cliente.** Com a chave 401 isso nem funcionaria, mas a
   regra vale mesmo assim.
6. **Não edite arquivo de outro worker.** A tabela de propriedade está na sua task. Precisa de algo
   fora dela? Use `ask`.
7. **i18n:** pt-BR é prioridade, `en` também preenchido. Zero texto hardcoded em componente.
8. **Conversa 1:1 e o resto do painel de conversa não podem mudar.** Regressão fora do copiloto é
   pior que o bug que estamos consertando.

---

## 6. Qualidade cobrada no fim

- **Ruby:** `bundle exec rubocop <arquivos>` limpo; specs verdes.
- **JS/Vue:** `npx eslint <arquivos>` limpo; specs vitest para o que criar.
- **Rode a suíte pré-existente dos arquivos que tocar** e diga honestamente o que já falhava antes
  (várias falhas desta base são pré-existentes — não tente consertar o mundo).
- **Honestidade:** se algo ficou pela metade ou não deu para testar por causa do 401, escreva isso.
  Relatório otimista custa caro depois.

---

## 7. Ao terminar

Relatório em `plano/captain-v2/relatos/<seu-id>.md`: o que mudou (arquivo:linha), como testou, o
que ficou de fora, riscos. Depois `worker_done` conforme o preâmbulo, com `filesModified` correto.
