import { mount } from '@vue/test-utils';
import WSurface from '../WSurface.vue';
import WBubble from '../WBubble.vue';
import WSkeleton from '../WSkeleton.vue';
import WBanner from '../WBanner.vue';

describe('WSurface', () => {
  it.each([
    ['flat', 'w-surface--flat'],
    ['raised', 'w-surface--raised'],
    ['sunken', 'w-surface--sunken'],
  ])('elevation %s aplica %s', (elevation, classe) => {
    expect(mount(WSurface, { props: { elevation } }).classes()).toContain(
      classe
    );
  });

  it('renderiza na tag pedida, para não forçar div em lista', () => {
    expect(mount(WSurface, { props: { as: 'section' } }).element.tagName).toBe(
      'SECTION'
    );
  });

  it('elevation inválida é recusada pelo validator', () => {
    expect(WSurface.props.elevation.validator('flutuante')).toBe(false);
  });
});

describe('WBubble', () => {
  it('direction é obrigatória — balão sem lado não existe', () => {
    expect(WBubble.props.direction.required).toBe(true);
  });

  it.each([
    ['incoming', 'w-bubble--incoming'],
    ['outgoing', 'w-bubble--outgoing'],
  ])('direction %s aplica %s', (direction, classe) => {
    const el = mount(WBubble, { props: { direction } });

    expect(el.classes()).toContain('w-bubble');
    expect(el.classes()).toContain(classe);
  });

  it('direction inválida é recusada', () => {
    expect(WBubble.props.direction.validator('lateral')).toBe(false);
  });
});

describe('WSkeleton', () => {
  it('fica fora do leitor de tela — quem anuncia carregamento é o WSpinner', () => {
    expect(mount(WSkeleton).attributes('aria-hidden')).toBe('true');
  });

  it('desenha uma linha por unidade pedida', () => {
    const el = mount(WSkeleton, { props: { lines: 3 } });

    expect(el.findAll('.w-skeleton__linha')).toHaveLength(3);
  });

  it('lines recusa zero, negativo e fracionário', () => {
    const { validator } = WSkeleton.props.lines;

    expect(validator(1)).toBe(true);
    expect(validator(0)).toBe(false);
    expect(validator(-2)).toBe(false);
    expect(validator(1.5)).toBe(false);
  });
});

describe('WBanner', () => {
  it.each([
    ['info', 'status'],
    ['warning', 'status'],
    ['error', 'alert'],
  ])('tone %s usa role=%s', (tone, role) => {
    // `alert` interrompe o leitor de tela: cabe em erro, não em informação.
    expect(mount(WBanner, { props: { tone } }).attributes('role')).toBe(role);
  });

  it('mostra o conteúdo do slot', () => {
    const el = mount(WBanner, {
      props: { tone: 'error' },
      slots: { default: 'Sem conexão' },
    });

    expect(el.text()).toBe('Sem conexão');
  });

  it('tone inválido é recusado', () => {
    expect(WBanner.props.tone.validator('roxo')).toBe(false);
  });
});
