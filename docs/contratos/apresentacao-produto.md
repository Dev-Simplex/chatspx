---
titulo: Contrato — `distribuicao_produtos.apresentacao`
status: PROPOSTO pela spx/rodizio · aguardando aceite da spx/followup
dono_da_tabela: spx/rodizio
consumidor: spx/followup
data: 2026-08-02
migration: 20260802143722
---

# Contrato — `apresentacao` (inventário de peças por produto)

> **Quem é dono do quê:** a tabela `distribuicao_produtos` é da **spx/rodizio** — por isso a
> migration nasce lá, pra não repetir a colisão de 30/07. O **conteúdo** desta coluna e quem a
> lê é da **spx/followup**. Este documento existe pra as duas frentes concordarem **antes** de
> alguém codar contra.

## 1. O princípio (não-negociável)

> **A config descreve MATERIAL e PÚBLICO. Nunca SEQUÊNCIA.**

Quem escolhe qual peça, para quem e quando é a **IA, no contexto**. Config com ordem, prazo ou
etapa engessa o comportamento e — pior — torna impossível **testar estratégia**: se a sequência
está no banco, comparar duas abordagens vira migração de dados em vez de mudança de conduta.

**Campos que NÃO entram aqui, por mais tentadores que pareçam:** `ordem`, `passo`, `dia`,
`apos_x_horas`, `proxima_peca`, `obrigatoria`, `etapa_do_funil`. Se aparecer a necessidade, a
resposta é conduta de prompt, não coluna.

## 2. Formato proposto

```json
{
  "publico": "<texto livre: pra quem este produto serve, em linguagem natural>",
  "pecas": [
    {
      "id":        "<identificador estável da peça>",
      "tipo":      "audio | carrossel | imagem | video",
      "descricao": "<o que esta peça explica e pra quem ela serve, em linguagem natural>"
    }
  ]
}
```

- **`publico`** — orientação de público do **produto inteiro**, texto livre. É contexto para a IA
  julgar encaixe, não filtro programático.
- **`pecas[].id`** — estável. É o que a spx/followup resolve para o material real no envio (ver
  §4, questão 1). Para a rodizio é **opaco**.
- **`pecas[].tipo`** — string livre com vocabulário documentado (os quatro acima). Deliberadamente
  **não** é enum de banco: formato novo não pode exigir migration.
- **`pecas[].descricao`** — o coração do desenho. É por ela que a IA decide. Descreve **o que a
  peça explica** e **para quem serve** — não quando usar.

**Ausente ou `{}`** = produto sem material. Comportamento atual, sem efeito nenhum.

## 3. ⚠️ Restrição de segurança na hora de expor isso à IA

Esta é a **Regra #1** do projeto e ela morde exatamente aqui:

> **Nenhum exemplo copiável na tool que expuser as peças.** Nem no `description`, nem em
> `param`. Descrever a **origem** do valor, nunca um valor.

Precedente real: um `(ex: 6573)` na descrição de um parâmetro fez a IA mandar **sempre** o imóvel
6573. Uma tool de peças com `id` de exemplo vai mandar sempre aquela peça — e o sintoma (a IA
"gostou" de um carrossel) é lento de diagnosticar porque parece escolha, não bug.

O mesmo vale para o conteúdo do banco: `descricao` deve descrever a peça, não conter script de
fala pronta que a IA vá recitar.

## 4. Questões abertas — precisam da spx/followup

1. **Como o `id` vira material no envio?** Attachment, resposta rápida (canned response), template
   HSM, URL? A rodizio trata como opaco; a decisão é da followup, e ela define se o contrato
   precisa de um campo a mais (ex.: `ref`) ou se o `id` já é a chave no repositório de vocês.
2. **Peça compartilhada entre produtos.** Com jsonb por produto, material que serve a dois
   produtos é duplicado. Aceitável no volume atual e coerente com config-first — mas se a
   followup previr reuso pesado, o desenho certo é uma tabela de peças com referência, e aí a
   migration muda. Melhor decidir agora que depois de popular.
3. **Vocabulário de `tipo`.** Os quatro cobrem hoje. Confirmar se falta algum (documento/PDF?
   áudio-narrado × áudio-depoimento contam como um só?).

## 5. Estado

- ✅ Migration escrita e **aditiva/inerte** — `20260802143722`, aplicar com alvo.
- ✅ Leitores no model `Spx::Distribuicao::Produto` (`publico_alvo`, `pecas`) — para as duas
  frentes lerem do mesmo lugar em vez de cada uma parsear o hash.
- ⏳ **Formato aguardando aceite da spx/followup.** Enquanto não houver aceite, ninguém deve
  popular a coluna: mudar formato com dado dentro custa migração de conteúdo.
