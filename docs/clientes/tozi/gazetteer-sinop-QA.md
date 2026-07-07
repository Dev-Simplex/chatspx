# Gazetteer Sinop - QA e pendencias

Fonte: workflow `gazetteer-sinop-tozi`. Este arquivo NAO vai pra IA - e o rastro de qualidade.

## Stats

```json
{
  "bairros_descobertos": 179,
  "bairros_enriquecidos": 179,
  "pontos_descobertos": 101,
  "pontos_enriquecidos": 100,
  "issues": 37,
  "suspeitos": 6
}
```

## Suspeitos de invencao (excluidos do mapa mental)

- Parque Florestal (na verdade e o Parque Ecologico/Florestal de Sinop — area verde dentro do Jardim das Primaveras, NAO um bairro residencial)
- Jardim Maringa II (atestacao fraca como bairro distinto de Jardim Maringa)
- Jardim das Nacoes II e III (so a base 'Jardim das Nacoes' e solidamente atestada; II/III fracos)
- Big Master Supermercados (rede real, mas SEM loja em Sinop — não é ponto de referência da cidade)
- Cachoeira Mercúrio (real, porém no município de Colíder, não em Sinop)
- Portais nacionais listados como referência física de Sinop: Viva Real, ZAP Imóveis, OLX, Chaves na Mão, Imovelweb, Wimoveis, Trovit, Mitula, Proprietário Direto, Campainha, Lopes (são sites/apps, não locais em bairro de Sinop)

## Apontamentos da verificacao adversarial (37 itens)

- **Parque Florestal** [invencao_mislabel]: Nao e bairro residencial. E o Parque Ecologico/Florestal de Sinop (area verde de lazer), que fica DENTRO do Jardim das Primaveras. Rotular como 'bairro residencial central' e erro de categoria — nao aparece como bairro em nenhuma base dos Correios.  ->  Remover da lista de bairros (ou mover para 'ponto de interesse').
- **Jardim Violetas** [duplicata_regiao]: Variante de 'Jardim das Violetas' (nome oficial nos Correios). A lista traz os dois. Alem disso a regiao conflita: 'Jardim das Violetas' esta como norte e 'Jardim Violetas' como leste — mesma entidade, duas regioes.  ->  Manter apenas 'Jardim das Violetas'; definir uma unica regiao.
- **Jardim das Acacias** [duplicata]: Nao consta nas bases CEP. Provavel variante de 'Residencial das Acacias' (essa tem faixa CEP 78553-240..285). A lista traz ambos.  ->  Consolidar em 'Residencial das Acacias'.
- **Jardim Florenca** [duplicata]: Variante de 'Residencial Florenca' (faixa CEP 78555-380..422). A lista traz os dois nomes para o mesmo lugar.  ->  Consolidar em 'Residencial Florenca'.
- **Alto da Gloria / Cidade Alta** [duplicata]: 'Alto da Gloria' duplica 'Loteamento Alto da Gloria', e 'Cidade Alta' duplica 'Loteamento Cidade Alta' — ambos os pares aparecem na lista referindo o mesmo lugar.  ->  Manter uma entrada de cada.
- **Moinhos dos Ventos / Moinho dos Ventos** [duplicata]: Mesma entidade (Residencial Moinho dos Ventos), grafada em singular e plural em duas entradas da lista.  ->  Manter uma so (grafia oficial: 'Moinho dos Ventos').
- **Recanto Suico** [duplicata]: Duplica 'Residencial Recanto Suico' (ambos na lista). Confirmado como bairro com CEP proprio, mas listado duas vezes.  ->  Manter uma entrada.
- **Residencial Sabrina** [duplicata]: Igual a 'Residencial Sabrina I' (base sem numero == etapa I). A lista traz Sabrina, Sabrina I, Sabrina II e Sabrina III — as tres numeradas sao reais, mas 'Sabrina' solto duplica a I.  ->  Remover 'Residencial Sabrina' solto; manter I, II, III.
- **Loteamento Menino Jesus** [duplicata]: Provavel duplicata do par 'Loteamento Menino Jesus I' / 'II' (base sem numero). So as versoes I e II constam nos Correios.  ->  Remover a base sem numero; manter I e II.
- **Jardim Araguaia** [duplicata]: Variante de 'Residencial Jardim Araguaia' (nome nos Correios). A lista traz os dois.  ->  Consolidar em 'Residencial Jardim Araguaia'.
- **Bairro Nossa Senhora de Fatima** [duplicata]: Provavel duplicata de 'Residencial Nossa Senhora de Fatima' (mesma localidade; mbi grafa 'Bairro...', cepbrasil grafa 'Residencial...'). Ambos na lista.  ->  Consolidar em uma entrada.
- **Centro** [duplicata_sobreposicao]: Nao consta como bairro formal nas bases dos Correios (mbi/cepbrasil nao listam 'Centro'); a area central oficial e 'Setor Comercial' (tambem na lista). Existe no uso coloquial, mas ha sobreposicao com Setor Comercial.  ->  Decidir se mantem 'Centro' e 'Setor Comercial' separados ou unifica.
- **Jardim das Nacoes II / Jardim das Nacoes III** [baixa_confianca]: So a base 'Jardim das Nacoes' tem faixa CEP consolidada. As variantes II e III tem atestacao fraca (podem ser subfases de loteamento ou over-split). Nao confirmei como bairros CEP distintos.  ->  Confirmar antes de tratar como bairros separados.
- **Jardim Maringa II** [baixa_confianca]: So 'Jardim Maringa' tem faixa CEP (78556-200..278). 'Maringa II' aparece em cadastro de imoveis mas com atestacao fraca como bairro distinto.  ->  Confirmar; possivel subfase da mesma area.
- **Camping Club vs Condominio Residencial Camping Club** [baixa_confianca]: As bases CEP listam as duas como entradas separadas, mas provavelmente sao a mesma localidade (condominio). A lista traz ambas.  ->  Verificar se sao distintos; possivel duplicata.
- **Jardim das Primaveras vs Jardim Primavera** [baixa_confianca]: Faceis de confundir. 'Jardim Primavera' (singular) tem CEP; 'Jardim das Primaveras' (plural) tambem parece existir (abriga o Parque Florestal). Provavelmente distintos, mas confirmar que nao e duplicata.  ->  Confirmar que sao dois bairros diferentes.
- **Cachoeira Mercúrio** [fora-de-sinop]: Não fica em Sinop. A cachoeira pertence ao município de Colíder-MT (~150 km de Sinop, acesso pela MT-320/MT-220). A própria lista já anota '(Colíder)'. É atração regional acessível a partir de Sinop, mas administrativamente é de Colíder.  ->  Remover da lista de pontos de Sinop, ou marcar explicitamente como atração de Colíder (não usar como referência de bairro de Sinop).
- **Big Master Supermercados** [nao-existe-em-sinop]: A rede Big Master não tem loja em Sinop. As 6 unidades ficam em Tangará da Serra (3), Nova Olímpia, Campo Novo dos Parecis e Rondonópolis. Não é referência comercial de Sinop.  ->  Remover. Referências reais de supermercado em Sinop: Assaí (Setor Industrial Norte), Rede Center Sul (Jardim das Violetas), Grupo Machado, Casa Aurora, Mercado Plazza.
- **Catedral Sagrado Coração de Jesus [orgao-publico]** [categoria-errada]: É uma igreja/catedral (Paróquia Catedral Sagrado Coração de Jesus, Diocese de Sinop), não um órgão público. Além disso duplica a entrada 'Catedral de Sinop [igreja]'. O bairro correto é Setor Comercial (Praça da Catedral, Av. Gov. Júlio Campos, CEP 78550-286), não 'Centro'.  ->  Reclassificar como [igreja], bairro Setor Comercial, e unificar com a entrada 'Catedral de Sinop'.
- **Igreja Matriz Santo Antônio [comercio-referencia]** [categoria-errada]: É uma igreja (Paróquia Santo Antônio, com relíquia de 1º grau), não 'comercio-referencia'. Existe e fica na região central, próxima à Praça da Bíblia (plausível).  ->  Reclassificar como [igreja].
- **Portais nacionais como comercio-referencia (Viva Real, ZAP Imóveis, OLX, Chaves na Mão, Imovelweb, Wimoveis, Trovit, Mitula Imóveis, Proprietário Direto, Campainha, Lopes)** [categoria-escopo-errado]: São portais/apps nacionais online (ou franquia nacional, no caso da Lopes), não pontos físicos de referência localizados em um bairro de Sinop. Atribuir a eles um bairro em Sinop é impróprio.  ->  Remover como pontos de referência físicos. Se a intenção é listar imobiliárias locais, usar as reais de Sinop: Tozi Imóveis, Santa Cruz Imóveis, Canto a Canto, X2 Negócios (Jardim Imperial), Encore, Morar Bem, Sinop Imóveis.
- **Aeroporto (duas/três entradas: 'Aeroporto Regional de Sinop' vs 'Aeroporto Municipal Presidente João Figueiredo (OPS/SBSI)')** [nome-duplicado]: São o mesmo aeroporto. O nome oficial é 'Aeroporto Municipal Presidente João Figueiredo' (não 'Regional'). Fica na Rodovia dos Pioneiros s/n (CEP 78556-190); não tem bairro urbano formal (algumas fontes citam região da Gleba/Glória). IATA OPS, ICAO SBSI.  ->  Unificar em uma entrada com o nome oficial (Municipal), IATA OPS / ICAO SBSI; bairro = sem bairro formal (Rodovia dos Pioneiros).
- **Estádio Municipal Massami Uriú (Gigante do Norte) [bairro=?]** [bairro-preencher]: Bairro estava como '?'/'não confirmado'. Confirmado: Setor Industrial Sul (R. Colonizador Ênio Pipino, 2133).  ->  Preencher bairro = Setor Industrial Sul.
- **Memorial Rogério Ceni [bairro=?]** [bairro-preencher]: Existe (inaugurado dez/2010) e fica na entrada do Estádio Gigante do Norte, logo no Setor Industrial Sul. Categoria [memorial] correta.  ->  Preencher bairro = Setor Industrial Sul (mesma localização do estádio).
- **Terminal Rodoviário Lindolfo Trierweiler [bairro=?]** [bairro-preencher]: Existe. Endereço atual na Av. das Palmeiras, 142 - Setor Industrial Norte (há endereço antigo no Setor Comercial, Av. Gov. Júlio Campos).  ->  Preencher bairro = Setor Industrial Norte (confirmar se ainda opera nesse endereço).
- **Hospital Regional de Sinop 'Jorge de Abreu' [bairro=?]** [bairro-preencher]: Bairro estava como '?'. Confirmado: Setor Comercial (Rua das Caviúnas, 1759, CEP 78550-098). Coincide com a outra entrada da lista que já traz 'Setor Comercial'.  ->  Preencher bairro = Setor Comercial e unificar com a entrada duplicada.
- **Parque Florestal de Sinop (Parque Ecológico) [bairro=?/R-11]** [bairro-corrigir]: Fica na área de reserva R-11, no bairro Jardim Primavera. Atenção: 'Jardim das Primaveras' (citado em uma fonte) NÃO consta como bairro oficial na base de CEP; o correto é 'Jardim Primavera'.  ->  Bairro = Jardim Primavera (área R-11).
- **Parque de Exposições da Acrinorte [bairro=não confirmado]** [bairro-preencher]: Existe (sede da Norte Show). Endereço: R. João Pedro Moreira de Carvalho, 6540 - Setor Industrial Norte. (Há projeto de novo parque perto do aeroporto, mas o atual é no Setor Industrial Norte.)  ->  Preencher bairro = Setor Industrial Norte.
- **Biblioteca Pública Municipal Professora Regina Helena Bongiovani Moscatto [bairro=não confirmado]** [bairro-preencher]: Existe. Endereço: Rua das Nogueiras, 230 - Setor Comercial. (Algumas fontes grafam 'Morgatto', mas o correto é 'Moscatto'.)  ->  Preencher bairro = Setor Comercial.
- **Rede Center Sul [bairro=?]** [bairro-preencher]: Existe em Sinop (ao contrário do Big Master). Endereço: Av. dos Jequitibás, 2670 - Jardim das Violetas.  ->  Preencher bairro = Jardim das Violetas.
- **Praça da Bíblia [praca] bairro=Centro** [bairro-divergente]: Fontes situam a Praça da Bíblia na Av. das Figueiras, Setor Industrial (borda com a área central), não 'Centro'. Há inconsistência interna: a lista também associa a Casa do Artesão à 'Praça da Bíblia' dizendo bairro=Centro.  ->  Rever para Setor Industrial (região central); alinhar com a Casa do Artesão.
- **Condomínio Portal do Servidor [bairro=Portal do Servidor]** [bairro-impreciso]: 'Portal do Servidor' é nome de condomínio, não bairro oficial (não consta na base de CEP de Sinop). O condomínio fica no Setor Comercial.  ->  Bairro = Setor Comercial; manter 'Portal do Servidor' apenas como nome do condomínio.
- **Carpe Diem Resort Residencial** [nome-desatualizado]: Existe (loteamento fechado alto padrão, próximo à UNIC/aeroporto, Av. dos Mognos), mas foi renomeado para 'Hamoa'. A categoria e o bairro-próprio estão corretos.  ->  Registrar nome atual: Hamoa (ex-Carpe Diem).
- **Edifício Angra dos Reis [comercio-referencia]** [bairro-confirmado]: É prédio residencial (72 aptos + lojas). Bairro correto: Setor Industrial Sul (Rua Colonizador Ênio Pipino, 1293, de frente para a Av. Alexandre Ferronato/Shopping). A divergência com 'Cidade Jardim' que a lista aponta se resolve: o correto é Setor Industrial Sul.  ->  Fixar bairro = Setor Industrial Sul; descartar 'Cidade Jardim'.
- **Praia do Cortado [parque]** [categoria-nota]: É praia fluvial no Rio Teles Pires, ~20 km do centro, acesso por estrada de terra (Estrada Nanci / MT-220). Zona rural, não é 'parque' urbano nem tem bairro.  ->  Categoria: praia/atração natural; sem bairro (zona rural), a ~20 km do centro.
- **UFMT / UNIC (campi) [faculdade]** [agrupamento-impreciso]: UFMT (pública, Av. Alexandre Ferronato, 1200, Setor Industrial) e UNIC (Universidade de Cuiabá, privada) são instituições distintas; agrupá-las como um 'campus' é impreciso. Ambas existem em Sinop. UNEMAT é ainda outra (Av. dos Ingás, 3001, Jardim Imperial).  ->  Separar UFMT (Setor Industrial), UNEMAT (Jardim Imperial) e UNIC (privada) em entradas próprias.
- **Duplicatas na lista** [duplicidade]: Vários pontos aparecem repetidos, às vezes com categoria/bairro divergentes: UNEMAT (~4x), UFMT (~4x), Aeroporto (3x), Estádio Massami Uriú (2-3x), Parque Florestal (3x), Catedral (2x, uma como igreja e outra como orgao-publico), Terminal (2x), Hospital Regional (2x), BR-163 (2x).  ->  Deduplicar antes de usar; manter a versão com bairro/categoria corretos.

## QA resumo (do sintetizador)

BAIXA CONFIANÇA / PRECISA GEOCODING REAL:
- Todo o bloco "long tail" (Residencial *, Loteamento *, Chácara *, Comunidade * e Jardins conf=baixa) entrou como nome-only, sem região/avenida/âncora confiável. A maioria dos "Residencial *" tem faixa popular provável mas localização não confirmada — precisa geocoding por CEP para atribuir região e corredor. ~90 nomes nesse estado.
- Faixa socioeconômica dos bairros conf=baixa é palpite de corretor, não medição; preço real só via API Vista (nunca deste mapa).

DUPLICATAS CONSOLIDADAS (mantive 1, descartei a variante — confirmar):
- Jardim Violetas = Jardim das Violetas (mantive "das Violetas" em Norte; havia conflito Norte×Leste).
- Jardim das Acácias = Residencial das Acácias.
- Jardim Florença = Residencial Florença.
- Alto da Glória = Loteamento Alto da Glória (mantive em Sul).
- Cidade Alta = Loteamento Cidade Alta (mantive em Sul).
- Moinhos dos Ventos = Moinho dos Ventos (grafia oficial singular).
- Recanto Suíço = Residencial Recanto Suíço (mantive em Norte).
- Residencial Sabrina = Sabrina I (descartei o solto; mantive I/II/III).
- Loteamento Menino Jesus = Menino Jesus I/II (descartei a base sem número).
- Jardim Araguaia = Residencial Jardim Araguaia.
- Bairro Nossa Senhora de Fátima = Residencial Nossa Senhora de Fátima.
- Camping Club = Condomínio Residencial Camping Club (mantive o condomínio, Norte).
- Centro × Setor Comercial: mantidos separados (coloquial × oficial dos Correios); podem ser unificados.

EXCLUÍDOS por suspeita de invenção / escopo errado:
- Jardim Maringá II e Jardim das Nações II/III (atestação fraca como bairros distintos — provável subfase).
- "Parque Florestal" como bairro: é o Parque Ecológico/Florestal (área verde dentro do Jardim Primavera, R-11); virou ponto de referência, não bairro.
- Big Master Supermercados (sem loja em Sinop) e Cachoeira Mercúrio (fica em Colíder) — removidos como referência.
- Portais nacionais (Viva Real, ZAP, OLX, Chaves na Mão, Imovelweb, Wimoveis, Trovit, Mitula, Lopes etc.) — são apps, não pontos físicos; substituídos pela lista de imobiliárias locais reais.

CONFLITOS DE REGIÃO NÃO RESOLVIDOS (checagem humana):
- UNEMAT/Jardim Imperial: enriquecido marca Oeste, PONTOS marca Central — coloquei em Oeste (borda central).
- IFMT: apontamento diz Setor Comercial (Central), mas Residencial Iguatemi (Norte) o cita como âncora — listado nas duas.
- Shopping Sinop e Estádio Massami Uriú: ficam no Setor Industrial (Sul/borda central), mas bairros do Oeste (Iporã, Curitiba, Copacabana) os usam como âncora.
- Fórum da Comarca: apontamento diz Setor Comercial (Central), mas condomínios Aquarela/Portal da Mata (Leste) o citam como vizinho — possível novo fórum no vetor leste.
- Praça da Bíblia / Casa do Artesão: divergência Centro × Setor Industrial (borda central).
- Terminal Rodoviário Lindolfo Trierweiler: endereço novo no Setor Industrial Norte × antigo no Setor Comercial — confirmar operação atual.
- Aeroporto: sem bairro urbano formal (Rodovia dos Pioneiros); região é vetor nobre leste apenas por direção.

NOTAS PONTUAIS:
- Carpe Diem foi renomeado "Hamoa" (alto padrão, vetor aeroporto/UNIC) — registrado.
- Regiões Central/Oeste/Norte/Leste/Sul são leitura de bússola de corretor, não divisão administrativa oficial de Sinop; tratar como aproximação até geocoding.
