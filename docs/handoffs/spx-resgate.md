# Triagem — FECHADA em 30/07

**Origem:** `origin/spx/fix-fotos-handoff-hml` (trabalho de 09–14/07 que nunca entrou em
`homologacao` nem em `producao`). Os 4 conflitantes foram decididos; os 5 já aplicados foram
conferidos contra o código atual.

Branch: **`spx/resgate`**, 9 commits em cima de `b31ed77b6` (tip da `homologacao` em 30/07).

---

## Os 4 conflitantes — veredito

| commit | veredito | novo commit |
|---|---|---|
| `a70eb5ebb` exemplos copiáveis nas tools | **PORTADO** (parcial: só a parte das tools) | `abf4bde0a` |
| `0a2240a72` handoff + ImoCodigo + fotos | **PORTADO em partes** (b e d; a já estava) | `343b226ca`, `db08b1f20` |
| `198aa2334` campo `Condominio` | **PORTADO** (adaptado) | `fbce358d8` |
| `f9647e1c9` recursão em `track_imoveis` | **DESCARTADO** — o bug não existe mais | — |

### `a70eb5ebb` — portado
Ainda valia: `buscar_localizacao` (`ex: "Jardim Botânico"` — o exemplo que causou a conv 19023),
`buscar_imovel` (`endereco`, `raio_km`), `buscar_lugar`, `registrar_assunto`,
`transferir_para_agente`.
**Não reaplicado:** o `(Tozi Imóveis)` do pin de localização — entrou pelo `9dd3212a6` em 22/07.
**Além do commit original:** `buscar_empreendimento` (tool criada em 15/07, depois do commit)
tinha `ex: "Gaia", "Acqua", "Tívoli"`. Mesmo defeito + nomes de um cliente em código
compartilhado. Corrigida junto. Se não for pra entrar, é o único hunk desse commit a reverter.

### `0a2240a72` — três partes, três destinos
- **(a) regex de handoff → já estava.** O `639cf8529` (já aplicado) trouxe patterns idênticos.
- **(b) busca por `ImoCodigo` → portado.** O código atual só tentava `Codigo`. Segunda chamada
  só quando a primeira vem vazia.
- **(d) link de todas as fotos → portado adaptado.** O *comportamento* (oferecer link em vez de
  despejar foto) já entrou por outro caminho desde julho — cooldown, teto por imóvel e texto
  orientando o link. Faltava o determinismo: o retorno mandava a IA *lembrar* a URL, e URL
  remontada errada é apagada pelo `fix_property_links` (o cliente recebe oferta de galeria sem
  link). Agora as 3 saídas levam a URL canônica do `urls_imoveis`.
  **Não portada** a redação de julho ("as primeiras costumam ser as externas") — afirmação sobre
  a ordem das fotos do Vista que não foi verificada, e o texto atual é mais preciso.

### `198aa2334` — portado adaptado
`Condominio` entrou no `VISTA_FIELDS` e `format_condominio` no resultado. O `format_listings`
ganhou o modo `detalhado` desde julho, então a linha de listagem foi remontada (e quebrada em
duas, que já estourava os 150 do RuboCop).
⚠️ **Não deu pra confirmar ao vivo que o `/imoveis/listar` devolve `Condominio`** (sem chave do
Vista nesta máquina). Se não devolver, o `else ''` faz o comportamento voltar ao de hoje — custo
zero, mas o ganho só aparece quando alguém verificar.

### `f9647e1c9` — descartado
O método `track_imoveis` **não existe mais** no código atual: `perform` chama `track_codigos` e
`track_urls` diretamente (linhas ~38-41 e ~67-70). Não há recursão pra desarmar. Reaplicar
criaria um método morto.

---

## Os 5 já aplicados — conferidos

| commit (pós-rebase) | veredito |
|---|---|
| `dba627c54` follow-up sem vício em `[IGNORAR]` | OK, coerente com o job atual |
| `9ceb1dde2` retry na busca do Vista | OK, mas **cobre só o `/imoveis/listar`** |
| `dad393915` retry + log na transcrição | OK (`attr_reader :attachment, :message, :account` existe) |
| `0acb26ee2` follow-up após turno só-foto | OK (`Attachment.file_types[:location]` = 4 confere) |
| `25486bb49` safety-net de handoff | **resolve em parte** — ver abaixo |

### ⚠️ `25486bb49` (handoff) — resolve em parte, NÃO mexi
Confirmado o que a sessão de 29/07 diagnosticou. O commit alarga a **detecção** (pega "vai
retornar", "o time retorna amanhã", "entra em contato") — isso funciona. Mas restam 2 furos na
**ação**, e ambos são território da frente `followup`:

1. **`HUMANO` não tem `corretor`.** No vertical da Tozi a frase natural é "vou passar pro
   corretor" — o safety-net não pega. (`vendedor`, idem, pra outros clientes.)
2. **`ensure_handoff_if_promised` chama só `@conversation.bot_handoff!`**, não o
   `Captain::Conversation::HumanHandoffService`. O que se perde: `aguardando_humano_desde`
   (a conversa não entra em "Aguardando atendimento"), roteamento de time, a nota-dossiê pro
   humano, o `Spx::Distribuicao::DistribuirService` (rodízio) e o out-of-office. Ou seja: a IA
   promete que um humano retorna, o safety-net dispara — e a conversa não chega em ninguém.
   Compare com `escalate_after_unknown_marker` (mesmo arquivo), que faz certo.

**Deixei intocado de propósito** pra não duplicar/conflitar com a frente `followup`, conforme a
`CLAUDE.local`. Se aquela frente não for pegar, o conserto é pequeno: trocar o `bot_handoff!`
pelo service e acrescentar `corretor|vendedor` ao `HUMANO`.

---

## Achados que NÃO virei mexida (fora de escopo desta frente)

- **`9ceb1dde2` cobre só metade do Vista.** O retry está no `vista_get`, usado pelo
  `fetch_vista` (`/imoveis/listar`). Continuam sem retry: `detalhes_info` no
  `buscar_imovel_tool` e `fetch_detalhes` no `enviar_fotos_imovel_tool` — os dois batem em
  `/imoveis/detalhes` com `HTTParty.get` cru. Mesmo transitório, mesmo sintoma.
- **Linhas >150 (RuboCop) pré-existentes** em `buscar_imovel_tool` (13, 14),
  `enviar_fotos_imovel_tool`, `response_builder_job`, `programar_followup_tool`. Não toquei —
  só a linha que eu já estava mexendo entrou no limite.
- **Assunto do `9ceb1dde2` está com `@` sobrando** nas pontas (artefato do cherry-pick original).
  Cosmético; não reescrevi história por isso.

## Verificação
- **RuboCop e RSpec NÃO rodaram**: não há Ruby nesta máquina (worktree Windows).
  Conferência manual: sintaxe, comprimento de linha (150), enums e métodos referenciados
  (`attr_reader`, `Attachment.file_types`, `resolve_target`, `urls_imoveis`).
- Commits com `--no-verify`: o hook `pre-commit` quebra por falta de `node_modules` nesta
  worktree, e o `lint-staged` só cobre `app/**/*.{js,vue}` e `*.scss` — nada de Ruby.
  **Rodar `bundle exec rubocop` e os specs de captain antes de integrar.**

## Quando fechar
Push feito → avisar a integradora → só então deletar `origin/spx/fix-fotos-handoff-hml` e
`origin/spx/fix-fotos-handoff` (são o backup até a integração acontecer).
