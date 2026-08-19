import { ref } from 'vue';
import { useAvailability } from '../useAvailability';

const mockIsOnline = vi.fn();
const mockIsInWorkingHours = vi.fn();
const mockUseCamelCase = vi.fn(obj => obj);

vi.mock('widget/helpers/availabilityHelpers', () => ({
  isOnline: (...args) => mockIsOnline(...args),
  isInWorkingHours: (...args) => mockIsInWorkingHours(...args),
}));

// O alvo acompanha o especificador que `useAvailability.js` importa: o bloco
// 2.18 cortou a aresta para `dashboard/composables/useTransformKeys` (era por
// onde o `@sentry/vue` entrava no grafo de first-paint do widget) e pos uma
// copia local no lugar. `vi.mock` casa por especificador, e um `vi.mock` de
// modulo que ninguem importa NAO reprova: ele simplesmente nao faz nada, e os
// exemplos passam a exercitar a implementacao real sem avisar. Este mock ficou
// orfao por uma corrida inteira de 2.529 exemplos verdes.
vi.mock('widget/composables/useTransformKeys', () => ({
  useCamelCase: obj => mockUseCamelCase(obj),
}));

describe('useAvailability', () => {
  const originalWindow = window.chatwootWebChannel;

  beforeEach(() => {
    vi.clearAllMocks();

    // Reset mocks to return true by default
    mockIsOnline.mockReturnValue(true);
    mockIsInWorkingHours.mockReturnValue(true);
    mockUseCamelCase.mockImplementation(obj => obj);

    window.chatwootWebChannel = {
      workingHours: [],
      workingHoursEnabled: false,
      timezone: 'UTC',
      utcOffset: 'UTC',
      replyTime: 'in_a_few_minutes',
    };
  });

  afterEach(() => {
    window.chatwootWebChannel = originalWindow;
  });

  describe('initial state', () => {
    it('should initialize with default values', () => {
      const { availableAgents, hasOnlineAgents, isInWorkingHours, isOnline } =
        useAvailability();

      expect(availableAgents.value).toEqual([]);
      expect(hasOnlineAgents.value).toBe(false);
      expect(isInWorkingHours.value).toBe(true);
      expect(isOnline.value).toBe(true);
    });
  });

  describe('with agents', () => {
    it('should handle agents array', () => {
      const agents = [{ id: 1 }, { id: 2 }];
      const { availableAgents, hasOnlineAgents } = useAvailability(agents);

      expect(availableAgents.value).toEqual(agents);
      expect(hasOnlineAgents.value).toBe(true);
    });

    it('should handle reactive agents', () => {
      const agents = ref([{ id: 1 }]);
      const { hasOnlineAgents } = useAvailability(agents);

      expect(hasOnlineAgents.value).toBe(true);

      agents.value = [];
      expect(hasOnlineAgents.value).toBe(false);
    });
  });

  describe('working hours', () => {
    const workingHours = [{ dayOfWeek: 1, openHour: 9, closeHour: 17 }];

    beforeEach(() => {
      window.chatwootWebChannel = {
        workingHours,
        workingHoursEnabled: true,
        utcOffset: '+05:30',
      };
    });

    it('should check working hours', () => {
      mockIsInWorkingHours.mockReturnValueOnce(true);
      const { isInWorkingHours } = useAvailability();
      const result = isInWorkingHours.value;

      expect(result).toBe(true);
      expect(mockIsInWorkingHours).toHaveBeenCalledWith(
        expect.any(Date),
        '+05:30',
        workingHours
      );
    });

    it('should determine online status based on working hours and agents', () => {
      mockIsOnline.mockReturnValueOnce(true);
      const { isOnline } = useAvailability([{ id: 1 }]);
      const result = isOnline.value;

      expect(result).toBe(true);
      expect(mockIsOnline).toHaveBeenCalledWith(
        true,
        expect.any(Date),
        '+05:30',
        workingHours,
        true
      );
    });
  });

  describe('config changes', () => {
    it('should react to window.chatwootWebChannel changes', () => {
      const { inboxConfig } = useAvailability();

      window.chatwootWebChannel = {
        ...window.chatwootWebChannel,
        replyTime: 'in_a_day',
      };

      expect(inboxConfig.value.replyTime).toBe('in_a_day');
    });
  });
});
