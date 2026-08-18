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
// O CSS entra por `App.vue`, e NÃO por um import direto de `woot.scss`.
// Motivo, medido: o `@config '../../../tailwind.widget.config.js'` do woot.scss é
// relativo ao arquivo que o PostCSS RECEBE — que em produção é o bloco
// `<style lang="scss">` de `widget/App.vue` (ver o aviso no topo do woot.scss).
// Importar o .scss direto muda essa base e o build falha com "config file does
// not exist". Importar o App.vue carrega exatamente o CSS que o visitante recebe.
import 'widget/App.vue';

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
        buttonLabel: 'Quero falar com um especialista agora',
        // O aceite fala em CONCLUIR: a página registra a submissão para o teste
        // poder afirmar que o fluxo terminou, e não só que coube na tela.
        onSubmit: values => {
          window.__captureSubmitted = values;
        },
      })
    );
  },
});

app.use(i18n);
app.mount('#app');
