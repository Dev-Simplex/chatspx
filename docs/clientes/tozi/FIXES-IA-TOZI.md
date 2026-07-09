# Fixes da IA Tozi — backlog de correções

> Fonte: análise da conversa de teste **525** (conta 3 / homologação, 25/06) + sessões anteriores.
> Cliente de teste pediu casa pra alugar perto de um "Mercado Machado", código de imóvel, link do site, endereço.

---

## ✅ Já corrigido (sessões anteriores, no ar em homolog 27e605843)
- **Typing/ordem das bolhas** — `min_delay_s: 2.5` no humanizer.
- **Fora do horário** — template não deixa mais dizer "chamando agora"; diz quando o time volta.
- **Amanda** — não nega/confirma nome de pessoa, acolhe + encaminha.
- **Re-handoff** — não duplica dossiê (guard de idempotência).
- **Handoff keeps-AI + anti-papagaio (backstop/replay-guard)** — deployado.

---

## 🔴 A FAZER (achados na 525)

### 1. Busca por CÓDIGO de imóvel — NÃO EXISTE (tooling)
- **Sintoma:** "Qual a casa do código 9819?" → *"não tenho informação"* / *"busquei aqui mas não encontrei"*.
- **Causa:** `buscar_imovel` filtra por bairro/tipo/valor/dormitórios/lat-lng — **não tem param `codigo`**. Não dá pra puxar um imóvel pelo código que o cliente vê no site.
- **Fix:** adicionar lookup por código (Vista API aceita filtro `Codigo` / endpoint de detalhe). Param `codigo` no `buscar_imovel` OU tool `buscar_imovel_por_codigo`.

### 2. Link do site FABRICADO/errado (prompt + verificar tool)
- **Sintoma:** "Me manda o link" → `https://www.tozimoveis.com.br/imovel/6573` → cliente: *"Errado esse link"*.
- **Causa:** ela **inventou** o link — domínio errado (**tozimoveis** com 1 "i", o certo é **toziimoveis**, 2 "i") + path inventado. NÃO usou a URL que o `buscar_imovel` retorna.
- **Fix:** prompt — NUNCA inventar link; usar SÓ a URL que a tool devolve. + Verificar que o `buscar_imovel` retorna a URL correta (`toziimoveis.com.br` + path certo).

### 3. Parou de responder em RECLAMAÇÃO (prompt — [IGNORAR] disparando errado)
- **Sintoma:** última msg do cliente *"Quero saber porque você não está fazendo buscas corretas"* → **silêncio** (fim da conversa).
- **Causa:** a conversa está em "aguardando humano" (marcador setado 18:09). O prompt manda `[IGNORAR]` pra "cobrança de espera/desabafo sem pergunta nova". A reclamação sobre a BUSCA caiu nessa regra → calou.
- **Fix:** o `[IGNORAR]` é só pra cobrança de **espera de humano**. Reclamação sobre o ATENDIMENTO/busca NÃO pode ser ignorada — tem que responder/corrigir ou escalar.

### 4. Endereço/rua de imóvel de LOCAÇÃO sonegado (prompt + verificar tool)
- **Sintoma:** *"Qual a rua dessa casa?"* → *"o consultor passa na visita"* (repetido). Cliente: *"Como assim não tem a rua de uma casa para alugar????"*. O imóvel TEM endereço (o cliente colou do site: *Rua Cora Carolina, Casa 10, Condomínio Portal do Servidor*).
- **Causa:** ela reteve o endereço (até disse "em locação a gente passa sim" e não passou). Ou a tool não retorna o campo `Endereco`, ou o prompt manda segurar.
- **Fix:** verificar se `buscar_imovel` retorna `Endereco`/`Bairro`. Se sim, prompt deve **liberar a rua em locação**. Se não, incluir o campo no retorno.

### 5. Proximidade com referência AMBÍGUA (rede/comércio) — tooling + prompt
- **Sintoma:** "perto de um Machado" → ancorou no **endereço do escritório** (Av. das Figueiras) e inventou *"Machado da Av. das Figueiras"* (não existe). Só funcionou depois que o cliente especificou "Machado primaveras".
- **Causa:** "Mercado Machado" é rede com ~7 unidades. O Geocoding (Google) busca só **endereço** → 1 ponto arbitrário. Sem referência válida, ela alucinou o escritório.
- **Fix tooling:** `buscar_lugares` (Places API New — Paulo ativando) OU Nominatim → lista as unidades ("achei 6 Machados: Tarumãs, Aeroporto... qual?").
- **Fix prompt:** SEMPRE geocodar a referência do cliente; **NUNCA** usar o endereço do escritório como referência de proximidade; rede ambígua → listar/perguntar antes.

### 6. Repetição byte-a-byte (papagaio) — investigar
- **Sintoma:** 18:41:26 repetiu IDÊNTICA a frase de 18:40:34 ("Você quer conhecer essa casa? Ou prefere..."). O anti-papagaio (backstop/replay-guard, deployado) **não pegou**.
- **Fix:** investigar por que o guard não capturou (talvez seja geração nova repetida, não replay de histórico).

### 7. Inventário possivelmente ALUCINADO — investigar (crítico)
- **Sintoma:** apresentou casas (Portal do Servidor 2q R$2000 cód 6573, Setor Residencial Norte 1q R$1300, Villa Verde 2q R$1800) com distâncias; o código 9819 "não achou" mas depois "viu na imagem" e descreveu igual.
- **Risco:** podem ser imóveis/códigos/distâncias **inventados** (as distâncias foram calculadas contra referência errada).
- **Fix:** verificar se o `buscar_imovel` está retornando imóveis REAIS do Vista (não alucinação) e se as distâncias batem. Guardrail anti-invenção de imóvel.
