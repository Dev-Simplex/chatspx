# Unidades: atalhos, agenda com efeito e lembrete — como validar

**O que entrou:** as três partes do plano de 31/08/2026 — atalhos de repetição na tela,
a agenda da unidade passando a valer na caixa de entrada, e o aviso antes da regra.
**Migrations:** 3 (duas colunas novas e a marca de aviso já enviado). **Flag:** nenhuma —
o efeito é opt-in **por unidade**.
**Estado:** no ar em `nicolas.chatspx.app`.

---

## 1. Atalhos de repetição (a tela)

Em **Configurações → Unidades → (uma unidade) → Regras de agenda**, o seletor "Repete"
agora se nomeia pela data escolhida, como no Google Agenda.

Escolha **31/08/2026** na data de início e abra o seletor. Ele tem que oferecer:

```
Não se repete · Todos os dias · De segunda a sexta ·
Semanal: toda segunda-feira · Mensal: na última segunda-feira ·
Anual: em 31 de agosto · Personalizar…
```

- Trocar a data para **02/09/2026** tem que reescrever os rótulos sozinho ("toda
  quarta-feira", "na 1ª quarta-feira", "em 2 de setembro").
- Escolher um atalho **não abre painel nenhum** — ele já preencheu tudo. A prévia
  embaixo mostra as próximas datas; confira que batem com o rótulo.
- **Personalizar…** abre o painel de sempre, agora com a frequência dentro dele
  ("a cada 1 [semana(s)]"), que é onde ela passou a morar.
- **Salvar por atalho e reabrir a regra**: ela abre em "Personalizar…" com os campos
  exatamente como o atalho os deixou. Isso é de propósito — a regra existente aparece
  inteira, sem a tela adivinhar de qual atalho veio.

## 2. A agenda passa a valer (o que muda de verdade)

Na aba de caixas da unidade há um interruptor novo: **"Aplicar esta agenda às caixas
de entrada"**, desligado por padrão.

**Desligado, nada muda** — é o estado de todas as unidades que já existem.

**Ligado**, a regra do dia vence o horário da caixa: no feriado da filial, a caixa
daquele número responde como fora do expediente e a mensagem automática de ausência
entra sozinha. Sem regra no dia, a caixa volta a decidir pelo próprio horário.

Para provar no console, sem esperar feriado:

```bash
cd /home/chatwoot/chatwoot && bundle exec rails runner -e production '
u = Account.find(1).units.find_by(name: "NOME DA UNIDADE")
caixa = u.inboxes.first
hoje = Time.current.in_time_zone(u.timezone).to_date
puts "antes:  #{caixa.out_of_office?}"
u.update!(applies_to_inboxes: true)
r = u.exceptions.create!(name: "Teste", starts_on: hoje, closed_all_day: true)
puts "com feriado hoje: #{caixa.reload.out_of_office?}   (esperado: true)"
r.destroy!; u.update!(applies_to_inboxes: false)
puts "depois: #{caixa.reload.out_of_office?}   (tem que voltar ao valor de antes)"'
```

Três coisas têm que ser verdade: a primeira e a última linha **iguais**, a do meio
**true**, e uma caixa **sem unidade** não pode mudar de resposta em nenhum momento.

## 3. O aviso na tela (o que aparece sem ninguém marcar nada)

No topo da lista de Unidades, uma faixa mostra **o que muda amanhã** em cada filial:

> **Amanhã na sua rede**
> **Alta Floresta** — Feriado (fechada o dia todo)

Ela é calculada no fuso de cada unidade (Cuiabá vira o dia uma hora depois de São
Paulo) e no navegador, sem consulta nova ao servidor. Aparece para quem abrir a tela,
tenha alguém configurado aviso ou não — se nenhuma unidade tiver regra amanhã, a faixa
simplesmente não existe.

## 4. O lembrete por e-mail

Cada regra tem **"Avisar a equipe"**, com duas opções: **Sem aviso** e **Na véspera**.
(Havia 3 e 7 dias; saíram — feriado de filial se resolve no dia anterior, e três
caminhos para a mesma decisão era escolha demais.) O aviso sai por **e-mail** para os
administradores da conta e para quem atende nas caixas daquela unidade.

> **Atenção ao testar:** o staging tem SMTP de verdade (`cloud55.mailgrid.net.br`).
> Numa unidade real isso são 14 pessoas recebendo e-mail. Para ver só o texto, mande
> para você mesmo com `AdministratorNotifications::UnitScheduleMailer.upcoming_rule(
> unidade, regra, data, ["seu@email"]).deliver_now`.

> **Mudança em relação ao plano:** o aviso ia pelo sino. A tela de notificações do
> Chatwoot é moldada para conversa — ela lê `primary_actor.meta.assignee` e, ao clicar,
> navega para `/conversations/<id>`. Uma regra de agenda ali dentro quebraria a lista
> ou levaria a uma conversa que não existe. Trocar isso é mexer numa tela usada o dia
> todo, por um aviso que é secundário. O e-mail reusa o caminho que já existe
> (`AdministratorNotifications`), não gasta bit de flag e não arrisca o sino.

Para testar sem esperar o cron das 8h:

```bash
cd /home/chatwoot/chatwoot && bundle exec rails runner -e production '
Units::ScheduleReminderJob.perform_now
puts UnitException.where.not(last_reminded_on: nil).pluck(:name, :last_reminded_on).inspect'
```

Crie antes uma regra para **amanhã** com aviso de **1 dia**. Rode o job: o nome dela
aparece na lista. **Rode de novo: nada muda** — a data já avisada fica em
`last_reminded_on`, então o aviso não sai duas vezes.

No staging o e-mail não chega a lugar nenhum (sem `SMTP_ADDRESS` configurado); o que
se prova aqui é a decisão do job. O texto do e-mail está em
`app/views/mailers/administrator_notifications/unit_schedule_mailer/upcoming_rule.liquid`.

## 5. O que não pode ter quebrado

- A lista de unidades continua marcando **"aberta agora"** no fuso de cada uma
  (a de Cuiabá uma hora atrás da de São Paulo).
- Regras antigas, criadas antes desta mudança, continuam abrindo e salvando.
- Caixa **sem unidade**: mensagem de ausência exatamente como antes.

## Specs

```
bundle exec rspec spec/services/units spec/jobs/units spec/models/inbox_unit_schedule_spec.rb \
                  spec/models/unit_spec.rb spec/models/unit_exception_spec.rb \
                  spec/controllers/api/v1/accounts/units_controller_spec.rb
→ 107 exemplos, 0 falhas

npx vitest run app/javascript/dashboard/routes/dashboard/settings/units/specs/
→ 75 testes, 0 falhas
```

**O detalhe que segura as duas pontas:** a avaliação da recorrência existe em Ruby
(`app/services/units/schedule_evaluator.rb`) **e** em JS (`unitSchedule.js`) — a tela
não pode ir à rede a cada 60 s. Para não divergirem, os casos moram em
`spec/fixtures/units/schedule_cases.json` e são rodados **pelos dois specs**. Regra
nova entra no fixture primeiro; se um lado mudar sozinho, um dos dois quebra.
