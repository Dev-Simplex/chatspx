import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { routes } from '../captain.routes';

vi.mock('../pages/CaptainPageRouteView.vue', () => ({ default: {} }));
vi.mock('../pages/AssistantsIndexPage.vue', () => ({ default: {} }));
vi.mock('../assistants/Index.vue', () => ({ default: {} }));
vi.mock('../assistants/settings/Settings.vue', () => ({ default: {} }));
vi.mock('../assistants/inboxes/Index.vue', () => ({ default: {} }));
vi.mock('../assistants/playground/Index.vue', () => ({ default: {} }));
vi.mock('../assistants/guardrails/Index.vue', () => ({ default: {} }));
vi.mock('../assistants/guidelines/Index.vue', () => ({ default: {} }));
vi.mock('../assistants/scenarios/Index.vue', () => ({ default: {} }));
vi.mock('../documents/Index.vue', () => ({ default: {} }));
vi.mock('../responses/Index.vue', () => ({ default: {} }));
vi.mock('../responses/Pending.vue', () => ({ default: {} }));
vi.mock('../tools/Index.vue', () => ({ default: {} }));

const flattenChildren = (route, accumulator = []) => {
  if (route.meta) {
    accumulator.push(route.meta);
  }
  if (route.children?.length) {
    route.children.forEach(child => flattenChildren(child, accumulator));
  }
  return accumulator;
};

describe('captain routes', () => {
  it('does not restrict routes by installation type', () => {
    const allMeta = routes.flatMap(route => flattenChildren(route));
    expect(allMeta.every(meta => !meta?.installationTypes)).toBe(true);
  });

  it('uses Captain V2 feature flag on protected routes', () => {
    const allMeta = routes.flatMap(route => flattenChildren(route));
    const featureFlags = allMeta.map(meta => meta?.featureFlag).filter(Boolean);

    expect(featureFlags).toContain(FEATURE_FLAGS.CAPTAIN_V2);
    expect(featureFlags.every(flag => flag === FEATURE_FLAGS.CAPTAIN_V2)).toBe(
      true
    );
  });
});
