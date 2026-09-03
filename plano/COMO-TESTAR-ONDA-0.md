# Como testar a Onda 0 — o merge da v4.16.2 e o terreno do redesenho

> **Estado:** Onda 0 executada. Aceites fechados por comando; validação em navegador na §7.
> **Ambiente:** VM de homologação (`192.168.8.232`). Conta de teste: **3**.
> ⚠️ **Nada foi pushado.** Tudo vive em branches locais desta VM. Ver §8 antes de qualquer deploy.
> ⚠️ Testar SÓ na conta 3. Não mexer em conta de cliente real.

---

## 1. O que esta onda fez, em uma tela

Trouxe o **Chatwoot v4.16.2** para dentro do fork (3.605 arquivos do upstream), auditou os
**558 arquivos de colisão** com cobertura 100%, e consertou o que o merge tinha quebrado em
silêncio. O widget **não mudou** — provado pixel a pixel.

O que você deve conseguir constatar testando: **o produto continua o mesmo, com o upstream
atualizado por baixo.** Se algo parecer "novo" na sua sessão de teste sem estar nesta lista, isso
é um achado e vale reportar.

---

## 2. O teste mais importante de todos, e leva 2 minutos

**Nenhuma das duas migrations que destroem dado de cliente pode rodar como o upstream a escreveu.**
Confirme antes de qualquer outra coisa:

```bash
cd /home/chatwoot/chatwoot-redesenho-merge

# 1) A que apagaria as FAQ pendentes do Captain — tem de MIGRAR, não deletar
grep -c "INSERT INTO captain_faq_suggestions" \
  db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb
# esperado: 1   (ela transfere as linhas para o fluxo novo ANTES de remover)

# 2) A que apagaria a integração de IA da conta — tem de ser no-op comentado
grep -c "perform_later" db/migrate/20260515000000_enqueue_validate_openai_hooks_job.rb
# esperado: 0   (o enfileiramento automático foi removido)
```

**Se o primeiro der 0 ou o segundo der 1, PARE e não faça deploy.** Um apaga FAQ pendente de
cliente; o outro apaga a integração OpenAI da conta inteira — com a chave dentro, sem `down`,
de forma assíncrona.

---

## 2.1 O teste que só funciona pelo IP real — e por que ele existe

**Não teste pelo `localhost`.** O `Rack::Attack` tem safelist para `127.0.0.1`, então metade do
caminho de requisição nem executa. Foi assim que um defeito que devolvia **HTTP 500 em toda
requisição de cliente real** passou por 4619 testes de unidade, pelos 16 snapshots, pela suíte Ruby
e por uma validação de navegador inteira — todos verdes, com o app quebrado.

```bash
# pelo IP da máquina, NUNCA por 127.0.0.1
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.8.232:3055/app/login
# esperado: 200.  Se vier 500, procure NoMethodError no log do Puma.
```

Vale como regra permanente: **toda validação que se pretenda conclusiva bate no IP real.**

---

## 3. A IA voltou a se comportar como a nossa (conta 3)

O merge trocou prompts e descrições de tool do Captain pelos do upstream. Isso **muda o
comportamento da IA em produção sem nenhum teste acusar**. Três coisas para conferir:

### 3.1 O handoff volta a acontecer

```bash
grep -n "Passa a conversa para um ATENDENTE HUMANO" \
  enterprise/lib/captain/tools/handoff_tool.rb
# esperado: 1 linha. Se sair vazio, voltou a descrição do upstream.
```

A descrição do upstream é mais restritiva (*"only when the customer requests…"*) e faz a IA
**quase nunca** transferir — nenhum lead chega ao humano. O comentário do nosso código que
condena exatamente essa descrição sobreviveu ao merge três linhas acima dela.

**Teste vivo:** numa conversa da conta 3, diga *"quero agendar uma visita"*. A IA deve chamar o
handoff. Com a descrição do upstream, ela responde e não transfere.

### 3.2 A conduta em pt-BR voltou

```bash
grep -c "^- " enterprise/lib/captain/prompts/assistant.liquid
```

O merge reduziu **13 regras de conduta em pt-BR a 3 bullets em inglês**. Confira no arquivo que as
regras de conduta estão de volta e em português.

> **Não "corrija" o que não é perda:** `current_datetime`, `business_status` e
> `business_hours_text` **saíram de propósito** do `assistant.liquid` para o
> `runtime_context.liquid`. É o design de *prompt caching* (prefixo estável × parte volátil), e
> está certo.

### 3.3 O link de imóvel da Tozi não é inventado

```bash
grep -c "fix_property_links" \
  enterprise/app/jobs/captain/conversation/response_builder_job.rb
# esperado: 2   (o método e a chamada)
```

O merge apagou esse método — e **deixou vivo o produtor do dado**, cujo comentário descreve o
consumidor apagado. Sem ele, a IA da Tozi volta a mandar **URL de imóvel inventada** ao cliente
final.

---

## 4. O painel (conta 3, navegador, light **e** dark)

| # | O que fazer | O que tem de acontecer |
|---|---|---|
| 1 | Abrir uma conversa com mensagem restrita a **outro** agente, em tela ≥1024px | O preview mostra **🔒 Conteúdo restrito** — nunca o texto cru. O card expandido do upstream foi neutralizado justamente porque não implementa esse isolamento |
| 2 | Configurações → Caixas de entrada → criar uma inbox de **site** | A cor nasce **verde `#2dc46f`** (a marca), não azul `#1f93ff` |
| 3 | Criar inbox de site **pela API** | Mesma cor verde. Era essa a incoerência: tela e API nasciam diferentes |
| 4 | Abrir config da inbox, **arrastar o seletor de cor**, sair **sem salvar** | Duas coisas: o preview **acompanha ao vivo** enquanto arrasta, **e** ao sair sem salvar a cor volta ao valor original |
| 5 | Deixar `allowed_domains` vazio | A tela **diz** o que acontece (com o campo vazio, o widget da conta pode ser embutido por qualquer site) |
| 6 | Painel em **inglês** | Nenhuma chave crua na tela (eram 39 chaves faltando) |
| 7 | Excluir uma conversa de teste | Ela **some de verdade**. Antes: a API respondia `200 OK` e a conversa continuava lá |
| 8 | Integrações → abrir **Editar** numa integração → salvar sem mexer na credencial | A credencial **continua no banco**. Este era o pior defeito da onda |
| 9 | Abrir o canvas de **Automações** | Carrega (prova o `optimizeDeps` restaurado no Vite) |
| 10 | Relatórios → **Baixar PDF** | Gera (prova o `dedupe html2pdf.js` restaurado) |
| 11 | Central de Ajuda embutida | Continua carregando após a refatoração de layout do upstream |

**Regra de aceite desta seção:** erro no console do navegador **reprova o item**. É a mesma regra
que o fixture anti-erro aplica nos testes automatizados — um "abriu sem travar" não é aprovação.

---

## 5. O widget não mudou — e isso foi medido, não presumido

Você não precisa testar o widget visualmente para esta onda. Ele foi comparado **pixel a pixel**
contra o baseline pré-merge:

- 16 cenários (4 telas × claro/escuro × desktop/mobile): **20 passed / 0 failed**
- Com tolerância **zero**: **10 dos 16 idênticos até o último pixel**; os 6 restantes divergem só
  em contorno de glifo, e metade alterna entre 0 e ~6.000 px entre execuções — isto é
  *antialiasing*, não mudança
- O fundo novo que o upstream adicionou (`bg-n-slate-2 dark:bg-n-solid-1`) pinta **exatamente a
  cor que o elemento já herdava** (`#17171A` no escuro), medido nos dois lados

Se quiser conferir você mesmo:

```bash
cd /home/chatwoot/chatwoot-redesenho-merge
pnpm exec playwright test --project=widget    # esperado: 20 passed (rodado na branch integrada)
```

> ⚠️ O harness usa **portas fixas** (3038/3999/8899). Dois worktrees não rodam isso ao mesmo
> tempo — se der `already used`, tem outra execução no ar.

**Uma ressalva honesta:** o `ArticleViewer` (o leitor de artigos dentro do widget) mudou de
`bg-white` para `bg-n-solid-1`, o que no tema escuro deixa de ser um retângulo branco cegante.
Isso é **melhoria do upstream**, mas fica **fora** da matriz de 4 telas — **não foi medido**.

---

## 6. O que roda por comando

```bash
cd /home/chatwoot/chatwoot-redesenho-merge

pnpm exec vitest --no-watch --no-cache        # 471 arquivos, 4619 passed / 0 failed
bin/vite build                                 # 8 entradas, conjunto idêntico ao baseline
pnpm run build:sdk                             # sdk.js sai IIFE, 29.014 B / 9.595 B gzip
ls db/migrate | cut -d_ -f1 | sort | uniq -d   # VAZIO — colisão trava o db:migrate da frota
```

**`eslint` e `rubocop` falham — e já falhavam antes do merge.** Os números foram medidos nos dois
lados para não confundir dívida antiga com regressão:

| | antes do merge | depois | delta do merge |
|---|---:|---:|---:|
| eslint | 741 (103 errors) | 786 (103 errors) | **+45 warnings, 0 errors** |
| rubocop | 659 offenses | 674 | **+15** |

**`rspec` tem 219 falhas**, das quais **+60 são do merge** (medidas nos dois lados; as outras 109
não foram medidas e não são extrapoladas). As três causas estão em
`plano/redesenho/execucao/onda-0-dod-merge.md` §5b.

---

## 7. Validação em navegador — já feita, e o ambiente ficou de pé

Relatório completo em `plano/redesenho/execucao/onda-0-validacao-navegador.md`. Resumo:

**8 de 10 verdes, em claro e escuro.** O app sobe com o merge dentro, o dashboard renderiza
conteúdo real (não casca), a config de inbox abre e o `#2dc46f` está no DOM. O único erro de
console é `HTTP 503 waha_connections` — **e não é regressão**: é o caminho documentado do próprio
controller quando o WAHA não responde, o arquivo não foi tocado por esta onda
(`git log f26db6ee81..HEAD` nele sai vazio), e o ambiente isolado não tem WAHA.

**O ambiente continua no ar para você conferir o resto sem montar nada:**

```
http://127.0.0.1:3055      usuário: val.onda0@teste.local
                           senha:   ValOnda0!Teste#2026
```

Serve para fechar os itens da §4 que exigem operador logado — canvas de Automações, exportar PDF,
o arraste do ColorPicker, o isolamento por agente com mensagem restrita real, e a Central de Ajuda.

Para derrubar quando não precisar:

```bash
pkill -f "rails server -b 127.0.0.1 -p 3055"
```

> O Puma da **3000 (homologação) não foi tocado** — conferido em 200 antes e depois.

> **Por que isso tem seção própria:** o Puma da porta **3000** desta VM serve a branch
> `homologacao`, **não** a nossa. Testar contra ele valida outro código. A validação sobe um
> **segundo Puma isolado na 3055** servindo o worktree do merge, com banco de teste dedicado.

---

## 8. Antes de qualquer deploy na frota — checklist que não é opcional

Levantado pelas auditorias. Nenhum destes é defeito do merge; são consequências que **só aparecem
no deploy**, e três delas falham **em silêncio**.

| # | Verificar | Se ignorar |
|---|---|---|
| 1 | `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` no `.env` de cada VM | Todo webhook para IP privado (WAHA interna, n8n, receptor local) e **as tools HTTP do Captain** param de funcionar — sem exceção visível |
| 2 | `FB_APP_SECRET` / `INSTAGRAM_APP_SECRET` no `InstallationConfig` | **401 em 100% dos webhooks do Instagram.** Silencioso |
| 3 | `WHATSAPP_APP_SECRET` no `InstallationConfig` | **401 nos webhooks** de `whatsapp_cloud` com embedded signup |
| 4 | `rake assets:precompile` **sempre** | O bloco 0.3 mudou o hash de **31 chunks**. Manifest velho = tela abre e a feature não existe |
| 5 | Templates de e-mail globais duplicados por `(name, template_type, locale)` | `add_inbox_scope_to_email_templates` **aborta o `db:migrate`** no meio da fila |
| 6 | `captain_documents.external_link IS NULL`, e URLs do mesmo assistant que só diferem depois do byte 255 | `change_captain_document_external_link_to_text` **aborta o `db:migrate`** |
| 7 | `captain_assistant_responses` com `status = 0` por VM | É a FAQ pendente que a migration corrigida vai **migrar** para o fluxo novo |
| 8 | `CAPTAIN_OPEN_AI_ENDPOINT` apontando para gateway que responde 401 em `/v1/models` | Se alguém rodar o job de validação à mão, ele apaga as integrações de IA da VM inteira |

**As migrations 5 e 6 são trava, não corrupção** — o deploy para no meio, com as anteriores já
aplicadas. Conferir antes é minutos; descobrir depois é madrugada.

---

## 9. O que esta onda deliberadamente NÃO fez

Registrado para ninguém "corrigir" achando que foi esquecimento:

- **Título do portal**: o merge devolveu `@portal.display_title(@locale)` no lugar do nosso
  `<title>SPX - CHAT</title>` fixo. **Fica assim.** Num produto white-label, o título do Help
  Center do cliente é o nome do portal **dele**, não a nossa marca cravada.
- **`assignment_v2`**: o upstream o ligaria por padrão em toda conta nova. **Voltou para
  desligado.** Adotar o motor v2 é decisão de produto legítima — mas se toma de propósito, não
  como efeito colateral de um merge.
- **Card de conversa expandido**: o do upstream foi **neutralizado**, não portado. Ele não
  implementa o isolamento por agente. Portar as 4 customizações é trabalho próprio, com id.
- **`swagger.json`** caiu de 353 para 90 paths e **não tem conserto barato**: o pipeline que
  gerava os 353 nunca foi versionado.
- **95 chaves i18n novas sem pt-BR**: dívida conhecida, não perda (0 chaves nossas foram
  destruídas).

---

## 10. Onde está o resto

| Documento | O que traz |
|---|---|
| `plano/redesenho/execucao/onda-0-RELATORIO.md` | o índice da onda, com todas as decisões |
| `plano/redesenho/execucao/RETOMAR.md` | branches, HEADs e o que falta |
| `plano/redesenho/execucao/onda-0-dod-merge.md` | os números, comando a comando |
| `plano/redesenho/execucao/onda-0-auditoria-*.md` | as seis auditorias, arquivo a arquivo |
| `plano/redesenho/execucao/onda-0-correcoes-pendentes.md` | os 26 itens, com fonte e evidência |
</content>
