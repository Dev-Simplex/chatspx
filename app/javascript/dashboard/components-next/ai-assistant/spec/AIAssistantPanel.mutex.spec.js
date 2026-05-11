/**
 * Mutex contract for the AI Assistant V2 rollout.
 *
 * The legacy `CopilotContainer` and the new `AIAssistantPanel` MUST NEVER
 * render at the same time. Dashboard.vue is responsible for the v-if/v-else
 * branch — this spec asserts the source of truth (the template rendered by
 * the Dashboard root) keeps that contract whatever the flag state is.
 *
 * It is a static-source spec (no Vue mounting) so it does not depend on the
 * full Vuex/i18n bootstrap.
 */
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

const DASHBOARD_PATH = path.resolve(
  __dirname,
  '../../../routes/dashboard/Dashboard.vue'
);

describe('AIAssistantPanel V1/V2 mutex (Dashboard.vue source contract)', () => {
  const source = fs.readFileSync(DASHBOARD_PATH, 'utf8');

  it('imports both AIAssistantPanel and CopilotContainer', () => {
    expect(source).toMatch(/import\s+AIAssistantPanel\s+from/);
    expect(source).toMatch(/import\s+CopilotContainer\s+from/);
  });

  it('renders AIAssistantPanel guarded by aiAssistantFlag', () => {
    expect(source).toMatch(/<AIAssistantPanel[^>]*v-if="aiAssistantFlag"/s);
  });

  it('renders CopilotContainer only as the v-else branch (mutex)', () => {
    // Find the AIAssistantPanel block + the immediately following
    // CopilotContainer occurrence and assert v-else is on the latter.
    const aiIdx = source.indexOf('<AIAssistantPanel');
    expect(aiIdx).toBeGreaterThan(-1);
    const after = source.slice(aiIdx);
    const containerIdx = after.indexOf('<CopilotContainer');
    expect(containerIdx).toBeGreaterThan(-1);
    const containerSnippet = after.slice(containerIdx, containerIdx + 200);
    expect(containerSnippet).toMatch(/v-else/);
  });

  it('does NOT render CopilotContainer without v-else anywhere else', () => {
    // Count <CopilotContainer occurrences and ensure all of them have v-else
    // (other than within string literals) — there should be exactly one.
    const matches = source.match(/<CopilotContainer[\s>]/g) || [];
    expect(matches.length).toBe(1);
  });
});
