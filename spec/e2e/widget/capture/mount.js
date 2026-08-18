/**
 * Página mínima do aceite do bloco 4.03 — "fluxo de 4 campos conclui em 375 px
 * sem scroll horizontal".
 *
 * Monta o `CaptureForm` REAL com o CSS REAL do widget (`woot.scss`, que carrega o
 * Tailwind pelo `@config` do bloco 1.08). Medir largura com CSS falso mediria o
 * CSS falso; por isso aqui não há nenhum estilo próprio além do que o widget já
 * aplica no `body`.
 */
import { createApp, h } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import CaptureForm from 'widget/capture/CaptureForm.vue';
// O CSS entra pelo shim `widget/wootStyles.harness.scss`, e não por `App.vue` nem por um
// import direto de `woot.scss`. A razão inteira (a base do `@config` do Tailwind, e os
// 3.862 módulos que o App.vue arrastava para o aquecimento) está no cabeçalho do shim.
import 'widget/wootStyles.harness.scss';

// Quatro campos, que é o número do aceite: nome, e-mail, WhatsApp e CPF — a
// combinação real de um fluxo de captura brasileiro (dois canais de contato, com
// a regra "e-mail OU WhatsApp" ativa, e um documento mascarado).
const FIELDS = [
  {
    name: 'nome',
    label: 'Nome completo',
    type: 'text',
    required: true,
    validator: 'junk_name',
    placeholder: 'Como podemos te chamar?',
  },
  {
    name: 'email',
    label: 'E-mail corporativo',
    type: 'email',
    required: true,
    validator: 'email',
    help_text: 'Usamos só para responder você.',
  },
  {
    name: 'whatsapp',
    label: 'WhatsApp com DDI',
    type: 'phone',
    required: true,
    mask: 'phone',
    validator: 'phone',
  },
  { name: 'cpf', label: 'CPF', type: 'text', mask: 'cpf', validator: 'cpf' },
];

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const app = createApp({
  render() {
    return h(
      'div',
      { class: 'conversation-wrap' },
      h(CaptureForm, {
        items: FIELDS,
        // Rótulo LONGO de propósito, e o comprimento tem procedência: com
        // `whitespace-nowrap` (o que o `.button` do widget traz), este texto mede 452 px
        // dentro de uma caixa de 343 px — medido em 18/08/2026. É o pior caso realista, o
        // CTA que o administrador escreve, e é o que faz o teste de transbordo ter o que
        // pegar. Com o rótulo curto anterior (272 px numa caixa de 343) não havia defeito
        // nenhum a detectar, e o teste passava tanto com a proteção quanto sem ela.
        buttonLabel:
          'Quero falar agora com um especialista da nossa equipe comercial',
        // O aceite fala em CONCLUIR: a página registra a submissão para o teste
        // poder afirmar que o fluxo terminou, e não só que coube na tela.
        onSubmit: values => {
          window.capturaEnviada = values;
        },
      })
    );
  },
});

app.use(i18n);
app.mount('#app');
