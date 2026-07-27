# MISSÃO: fim das threads quebradas (9º dígito) + triagem com procedência

> Abrir sessão no repo principal (`chatspx/`), partir da **`homologacao`** atualizada, commit direto
> nela (Conventional Commits PT). ⚠️ Push desce ao vivo pra `.232` (contas 3/4/5). Validar na conta 3.
> Enterprise overlay: SEMPRE `rg` nas duas árvores (`app` + `enterprise`) antes de editar.

## Caso provado (22/07, conta 6 — diagnóstico da sessão ORQUESTRADOR)

Adrian (User#63) mandou template `tozi_venda_abertura` pela conversa **resolvida** 10820 (21/07
10:24). **No minuto do envio nasceu um 2º contact_inbox (58847)** com o fone COM 9º dígito
(`5545998247428`); o CI original (50054, de 22/05) é SEM o 9 (`554598247428`). A resposta da cliente
(10:31) casou com o CI novo → sem conversa lá → `lock_to_single_conversation=true` não segura (lock é
POR contact_inbox) → **conversa nova 19765** → regra de automação 55 (`conversation_created` inbox 91
→ `assign_ai_agent` Clara #7) → a IA assumiu um lead que o humano estava trabalhando (e que ele tinha
acabado de se auto-atribuir na 10820). **Magnitude: 333 pares contato+inbox com CI duplicado na conta
6; 162 no padrão 9º dígito; 15 conversas nasceram em CI duplicado nos últimos 30d.**

Scripts de diagnóstico (na VM Tozi, `/tmp/`): `diag_19765.rb`, `diag_ci.rb`, `diag_dupes.rb`.

## Item 1 — Fechar a fonte NOVA de duplicatas: envio de template 1:1 (a causa)

O fluxo "Enviar Template" de dentro da conversa criou o CI duplicado a partir do telefone do contato,
ignorando o CI que a conversa já tem. Achar o caminho (o CI 58847 nasceu no request do envio — buscar
quem chama builder de contact_inbox nesse fluxo) e corrigir: **enviar template de uma conversa
existente REUSA o contact_inbox da conversa** — nunca cria outro. Se houver outros caminhos que criam
CI a partir de fone (ex.: nova conversa pelo painel), normalizar antes de criar: casar as DUAS
variantes BR (com/sem 9) — já existem `Whatsapp::PhoneNumberNormalizationService` e
`Contacts::BrazilPhoneNormalizer` no fork; REUSAR, não inventar terceiro normalizador.

## Item 2 — Reconciliador de incoming (defesa no outro lado)

Implementar o item do BACKLOG `docs/backlog/reconciliador-incoming-9-digito.md` (tem análise + código
proposto): quando um wa_id inbound casa com 2+ fichas (variantes 12d/13d), rotear pra ficha da
**conversa mais recente** (hoje devolve a 1ª que casar — pode ser a errada). Preservar o caso comum
(`matches.one?`). Promovido de 🟢→🔴 no BACKLOG por causa deste incidente.

## Item 3 — Triagem com PROCEDÊNCIA (a guarda de produto)

A regra de triagem (`assign_ai_agent` em `conversation_created`) é cega pra quem iniciou o contato.
Ensinar procedência — decisão determinística, SEM LLM:

| Origem da resposta do cliente | Dono |
|---|---|
| Template de **campanha** (1:N — outra conversa do contato tem template recente com `campaign_id`/disparo) | **IA tria** (comportamento atual — ela entende se é sobre o disparo ou outro assunto e roteia) |
| Template mandado por **HUMANO** (1:1 — última msg outgoing de template pro contato em <24h tem `sender` User) | **O humano que mandou** (atribui a ele; time dele se houver). IA NÃO assume |
| Sem template recente (conversa orgânica) | **IA tria** (atual) |

Implementar a guarda no handler da action `assign_ai_agent` (cobre as regras 55/64 e futuras — achar
onde a action executa no fork, provável listener/serviço de automação). **Opt-in por conta** (chave de
config; se escrever em `custom_attributes`, usar `jsonb_set` atômico — gotcha do incidente 21/07,
NUNCA read-modify-write da hash inteira). Default = comportamento atual (guarda desligada) pra não
mudar outras contas.

## Fora de escopo (registrado, NÃO fazer aqui)

- **L1 dedup dos 333 pares existentes** — script de migração de dados, só com OK explícito do Paulo.
- **v2 da guarda: "delegação com brief"** (humano manda template passando contexto pra IA dar
  sequência se ele estiver offline, conversa em "aguardando atendimento") — ideia registrada no
  `.claude/BACKLOG.md` §IA como extensão do atendimento humano. A v1 (rotear pro humano) sai AGORA;
  a v2 é evolução consciente.

## Critério de aceite (provar na conta 3 / `.232`)

1. Enviar template de uma conversa existente NÃO cria contact_inbox novo (checar count antes/depois).
2. Resposta inbound de contato com fichas 12d/13d cai na conversa/ficha certa (mais recente).
3. Com a guarda ligada na conta de teste: conversa nova nascida de resposta a template HUMANO <24h →
   atribuída ao humano remetente (IA não responde); resposta a template de CAMPANHA → IA tria normal.
4. Guarda desligada = comportamento idêntico ao atual (regressão zero pras outras contas).
5. `bundle exec rubocop -a` limpo nos arquivos tocados · `rg` nas duas árvores feito · STATE.md
   atualizado (seção do incidente 22/07 → marcar o que foi resolvido).
