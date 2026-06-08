import { ref } from 'vue';
import { describe, it, expect } from 'vitest';
import { isDefaultStage, useKanbanStage } from '../useKanbanStage';

describe('isDefaultStage', () => {
  it('returns true for automation_type "open"', () => {
    expect(isDefaultStage({ automation_type: 'open' })).toBe(true);
  });

  it('returns true for automation_type "resolved"', () => {
    expect(isDefaultStage({ automation_type: 'resolved' })).toBe(true);
  });

  it('returns true for camelCase automationType', () => {
    expect(isDefaultStage({ automationType: 'open' })).toBe(true);
  });

  it('returns true for legacy name "Abertos"', () => {
    expect(isDefaultStage({ name: 'Abertos' })).toBe(true);
  });

  it('returns true for legacy name "Resolvidos"', () => {
    expect(isDefaultStage({ name: 'Resolvidos' })).toBe(true);
  });

  it('returns true for legacy name "Em Andamento"', () => {
    expect(isDefaultStage({ name: 'Em Andamento' })).toBe(true);
  });

  it('returns false for nil', () => {
    expect(isDefaultStage(null)).toBe(false);
    expect(isDefaultStage(undefined)).toBe(false);
  });

  it('returns false for custom stage without automation', () => {
    expect(isDefaultStage({ name: 'Custom', automation_type: null })).toBe(
      false
    );
  });
});

describe('useKanbanStage', () => {
  it('exposes isDefault as computed when given a ref', () => {
    const stage = ref({ automation_type: 'open' });
    const { isDefault } = useKanbanStage(stage);
    expect(isDefault.value).toBe(true);

    stage.value = { automation_type: null };
    expect(isDefault.value).toBe(false);
  });

  it('accepts a plain object too', () => {
    const { isDefault } = useKanbanStage({ automation_type: 'resolved' });
    expect(isDefault.value).toBe(true);
  });
});
