# Handoff — sessão orquestradora geral · 15/08/2026

> Handoff **corrente**. Substitui o de 14/08, que fica como histórico.
> Complementa `docs/ORQUESTRACAO-ORCA.md` (a prática) e `.claude/STATE.md` (o in-flight detalhado).

---

## 1. O que mudou de verdade nesta sessão

Três coisas que o handoff de ontem dava como travadas, e não estão mais:

1. **O deploy da homologação saiu.** Estava suspenso desde 13/08 por causa do trabalho off-git na
   `.232`. Foi resgatado, conciliado (PR #51) e deployado **duas vezes** — a box está em
   `59aba4a89f`. O trabalho que só existia lá (SSE do Copilot, grupos, backoff de LID) agora é
   código de verdade.
2. **A produção da Tozi recebeu um hotfix cirúrgico** (PR #55), sem arrastar os commits que
   aguardam a promoção do Walisson.
3. **O crédito da Anthropic da `.232` foi comprado pelo Paulo** — as contas 1, 3 e 7 voltaram a
   ter IA. Sem isso, tudo naquela box era mudo.

---

## 2. 🔴 Três silêncios da mesma família — o padrão mais importante do dia

Em 24 horas apareceram **três** defeitos com o mesmo desenho: **o sistema falhou e pareceu normal.**

| onde | o que acontecia | estado |
|---|---|---|
| carrossel de fotos no Instagram | saía como **texto** (`📷 Carrossel: 9 fotos…`), sem anexo e sem falha; a tool devolvia "enviei" e a IA garantia ao cliente | corrigido, **#49 mergeado** |
| chave de LLM sem saldo | saída vazia gravada como `ignored` — idêntico a um silêncio deliberado | corrigido, **#52 mergeado** |
| envio ao Instagram que levanta exceção | ia só para o tracker; a mensagem seguia como **enviada** | **#56 aberto** |

**A lição operacional:** ao investigar "a IA não fez X", desconfiar primeiro de falha invisível, não
de conduta. E ao construir, perguntar sempre *"se isto falhar, alguém vê?"*.

---

## 3. ⚠️ Duas conclusões minhas que a medição derrubou — leia antes de confiar em sonda

1. **"A IA ignora o contexto do vídeo."** Falso. Minha sonda montava o histórico como **texto puro**;
   o `ResponseBuilderJob` monta com `prepare_multimodal_message_content`. A leitura nunca chegava ao
   modelo **no teste**. Sonda de agente tem que replicar o caminho do job.
2. **"A conduta velha impedia o uso do vídeo."** Falso. Mesmo com o prompt dizendo *"você não
   enxerga nada"*, o modelo **seguiu a evidência do contexto**. Instrução obsoleta não bloqueou.

Some-se a isto o `dry_run` do Almirante mentindo sobre a `.232` (disse "1 commit, migrations em dia";
eram **328 commits e 10 migrations**) e a regra fica: **medir na box, e desconfiar da própria sonda
antes de acusar o sistema.**

---

## 4. Estado do código

**Mergeado hoje:** #45 (mídia→contexto), #49 (fotos por canal + ImoCodigo), #50 (vídeo: quadros +
transcrição), #51 (conciliação da `.232`), #52 (4 specs parados + `ignored`→`error`), #54 (menção),
#55 (o #54 na produção).

**Aberto:** **#53** (cache por story — o mesmo story é lido uma vez, não uma por pessoa) · **#56**
(falha de envio por exceção) · e a fila antiga do Walisson: **#46** (acesso indevido no copilot,
111× — o de maior valor), **#43**, **#44**, **#40**, **#41** (refactor, não urgente), **#42** (docs).
Os zumbis **#1–#7** são de maio, três em conflito: recomendo fechar.

⚠️ **Não medi #46/#43/#44/#40.** São de sessões anteriores; mergeá-los é entrar no escuro num deploy
sobre contas reais.

---

## 5. O que está no ar e o que não está

- **`.232`** (`59aba4a89f`): camada de mídia completa, vídeo lendo story, `ignored`→`error`, menção
  travada. **BigStore com `video_description` e `video_transcription` LIGADOS** (conta 7,
  assistente 18) — provado num story real: os quadros deram o produto, o áudio deu o preço.
- **Tozi produção** (`142564790`): só a trava da menção. **Não tem a camada de mídia** — lá a IA
  segue cega a vídeo, e é por isso que dizia "não consegui visualizar".
- **Fábrica**: intocada, 249 commits atrás.

---

## 6. Pendências por dono

**Paulo:** decidir o **vídeo na Tozi** (depende da promoção) · as **31 conversas de menção** já
poluídas, que seguem abertas · e o `ENV['OPENAI_API_KEY']` da produção da Tozi, que está **vazio** —
quando a camada de mídia chegar lá, ela será no-op silencioso até isso ser setado.

**Walisson:** a promoção `homologacao` → `producao` (as branches divergiram: **6 commits só na
produção, 23 só na homologação**, e o custo do merge cresce) · a fila de PRs.

**Sem dono:** os 8 testes de agrupamento em grupo que ficaram fora do #51 (estão em
`backup/232-offgit-20260814`) · os **Flows**, que montam `interactive_payload` sem perguntar pelo
canal — mesmo buraco do #49 · `copilot/assign_conversation_service.rb:27`, que seta `team_id` sem
validar conta.

---

## 7. Armadilhas novas (as de 14/08 continuam valendo)

1. **`git diff A...B` (três pontos) mede contra a base de merge**, não contra o topo. Foi assim que o
   handoff de ontem atribuiu ao #41 uma vermelhidão que não era dele. Use dois pontos.
2. **A branch `producao` LOCAL deste notebook está 297 commits atrás** — e a worktree
   `chatspx-clientes/tozi-prod` está nela. Worktree criada com `--base-branch producao` nasce morta.
   Sempre `origin/producao`.
3. **A VM da Tozi não tem credencial git.** Transporte por `git bundle`, nunca scp de arquivo solto —
   foi o scp que criou o off-git que custou um dia para reconciliar.
4. **Precompile precisa de `NODE_OPTIONS=--max-old-space-size=8192`** na `.232`; com 4096 estoura sem
   mensagem legível.
5. **`grep -c down` no `migrate:status` conta "bulk down*loads*"** como pendência. Use `'^  down'`.
6. **O hook de pré-commit local está quebrado** (`.husky/_` ausente): sai 1 e bloqueia commit. O
   `AGENTS.md` autoriza `--no-verify` nesse caso; o lint tem que ser medido na box.
7. **Crase em mensagem de commit via heredoc no Bash do Windows vira substituição de comando** e
   engole a palavra. Escreva a mensagem num arquivo e use `-F`.

---

## 8. O que funcionou e vale repetir

**Mutação, não só verde.** Todo PR desta sessão foi medido revertendo o próprio commit e conferindo
que os exemplos novos ficam vermelhos. Foi isso que pegou o bug de ordem do `orphan_retriage` — um
conflito **semântico** que o merge textual resolveu limpo e errado.

**Declarar a lacuna em vez de escondê-la.** No #51, duas bancadas de teste incompatíveis no mesmo
arquivo: em vez de improvisar uma fusão, ficou a da homologação e os 8 testes do outro lado foram
registrados como dívida nomeada.

**Prova sem enviar.** `generate_response` roda o agente sem criar mensagem: dá para provar conduta em
conversa real de cliente sem que ninguém receba nada.
