import { rotuloLimpo, rotuloObrigatorio } from '../rotulos';
import WIconButton from '../WIconButton.vue';
import WSpinner from '../WSpinner.vue';
import WField from '../WField.vue';
import WComposer from '../WComposer.vue';
import WScrollToBottom from '../WScrollToBottom.vue';
import WTeaserCard from '../WTeaserCard.vue';
import WButton from '../WButton.vue';

describe('rótulo acessível dos primitivos', () => {
  it('aceita texto limpo', () => {
    expect(rotuloObrigatorio('Fechar o chat')).toBe(true);
    expect(rotuloObrigatorio('Ver mensagens novas')).toBe(true);
  });

  it('recusa emoji — o leitor de tela anuncia o símbolo', () => {
    // O caso real veio do `CSAT.RATINGS.*`, que carrega emoji na string.
    expect(rotuloObrigatorio('😀 Muito satisfeito')).toBe(false);
    expect(rotuloObrigatorio('Enviar 🚀')).toBe(false);
    expect(rotuloObrigatorio('⭐')).toBe(false);
  });

  it('recusa rótulo vazio ou só espaço quando é obrigatório', () => {
    expect(rotuloObrigatorio('')).toBe(false);
    expect(rotuloObrigatorio('   ')).toBe(false);
  });

  it('acento e pontuação de pt-BR continuam válidos', () => {
    expect(rotuloObrigatorio('Configurações')).toBe(true);
    expect(rotuloObrigatorio('Não enviar')).toBe(true);
    expect(rotuloObrigatorio('Ação — desfazer')).toBe(true);
  });

  it('o rótulo opcional pode ser vazio, mas não pode ter emoji', () => {
    expect(rotuloLimpo('')).toBe(true);
    expect(rotuloLimpo('Enviando')).toBe(true);
    expect(rotuloLimpo('Enviando 📨')).toBe(false);
  });

  it.each([
    ['WIconButton', WIconButton, 'label'],
    ['WSpinner', WSpinner, 'label'],
    ['WField', WField, 'label'],
    ['WComposer', WComposer, 'label'],
    ['WScrollToBottom', WScrollToBottom, 'label'],
    ['WTeaserCard', WTeaserCard, 'dismissLabel'],
  ])('%s valida a prop %s', (_nome, componente, prop) => {
    const { validator } = componente.props[prop];

    expect(validator('Texto limpo')).toBe(true);
    expect(validator('Texto com 🎉')).toBe(false);
  });

  it('WButton valida o loadingLabel', () => {
    expect(WButton.props.loadingLabel.validator('Enviando')).toBe(true);
    expect(WButton.props.loadingLabel.validator('Enviando ⏳')).toBe(false);
  });
});
