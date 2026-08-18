# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: widget/widget.spec.js >> home-light-mobile
- Location: spec/e2e/widget/widget.spec.js:151:7

# Error details

```
Error: expect(received).toEqual(expected) // deep equality

- Expected  - 1
+ Received  + 1

  Object {
-   "critical": 1,
+   "critical": 0,
    "serious": 2,
  }
```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - main "Página hospedeira determinística" [ref=e2]:
    - heading "Atendimento Simplex" [level=1] [ref=e3]
    - paragraph [ref=e4]: Chassi real do SDK carregado após o conteúdo da página.
  - iframe [ref=e6]:
    - generic [ref=f1e5]:
      - banner [ref=f1e7]:
        - button "Fechar o chat" [ref=f1e10] [cursor=pointer]:
          - img [ref=f1e11]
        - heading "Como podemos ajudar?" [level=2] [ref=f1e13]
        - paragraph [ref=f1e14]:
          - paragraph [ref=f1e15]: Atendimento humano, simples e direto.
      - generic [ref=f1e17]:
        - generic [ref=f1e18]:
          - generic [ref=f1e19]:
            - generic [ref=f1e20]: Estamos conectados.
            - generic [ref=f1e21]: Normalmente responde em alguns minutos
          - img [ref=f1e25]:
            - generic [ref=f1e26]: ML
        - button "Continuar conversa" [ref=f1e27] [cursor=pointer]:
          - generic [ref=f1e28]: Continuar conversa
```

# Test source

```ts
  93  | 
  94  |   const iframe = page.locator('#chatwoot_live_chat_widget');
  95  |   const frame = page.frameLocator('#chatwoot_live_chat_widget');
  96  |   await expect(iframe).toBeAttached();
  97  |   await expect(frame.locator('#app')).toBeVisible();
  98  |   await expect
  99  |     .poll(
  100 |       () =>
  101 |         frame
  102 |           .locator('body')
  103 |           .evaluate(() =>
  104 |             Boolean(window.WOOT_WIDGET?.$router && window.WOOT_WIDGET?.$store)
  105 |           ),
  106 |       { timeout: 30000 }
  107 |     )
  108 |     .toBe(true);
  109 | 
  110 |   if (view !== 'unread') {
  111 |     await page.evaluate(() => window.$chatwoot.toggle('open'));
  112 |     await expect(page.locator('#cw-widget-holder')).not.toHaveClass(
  113 |       /woot--hide/
  114 |     );
  115 |     await frame.locator('body').evaluate(async (_body, routeName) => {
  116 |       await window.WOOT_WIDGET.$router.replace({ name: routeName });
  117 |     }, view);
  118 |   } else {
  119 |     await expect(page.locator('#cw-widget-holder')).toHaveClass(
  120 |       /has-unread-view/
  121 |     );
  122 |   }
  123 | 
  124 |   await expect
  125 |     .poll(
  126 |       () =>
  127 |         frame
  128 |           .locator('body')
  129 |           .evaluate(() => window.WOOT_WIDGET?.$router?.currentRoute.value.name),
  130 |       { timeout: 30000 }
  131 |     )
  132 |     .toBe(view === 'unread' ? 'unread-messages' : view);
  133 |   const anchor = frame.getByText(anchorByView[view], { exact: true });
  134 |   await expect(anchor).toBeVisible();
  135 |   if (view === 'unread') {
  136 |     await expect(
  137 |       frame.getByText('Ver novas mensagens', { exact: true })
  138 |     ).toBeVisible();
  139 |   }
  140 |   await frame.locator('body').evaluate(() => document.fonts.ready);
  141 |   if (theme === 'dark') {
  142 |     await expect(frame.locator('#app > .dark')).toBeAttached();
  143 |   }
  144 |   return { anchor, frame, iframe };
  145 | };
  146 | 
  147 | views.forEach(view => {
  148 |   themes.forEach(theme => {
  149 |     viewportNames.forEach(viewportName => {
  150 |       const scenario = `${view}-${theme}-${viewportName}`;
  151 |       test(scenario, async ({ page }) => {
  152 |         const { anchor, frame } = await prepareScenario(
  153 |           page,
  154 |           view,
  155 |           theme,
  156 |           viewportName
  157 |         );
  158 |         const holder = page.locator('#cw-widget-holder');
  159 |         await expect
  160 |           .poll(async () => {
  161 |             const hostAnimations = await holder.evaluate(
  162 |               element =>
  163 |                 element
  164 |                   .getAnimations({ subtree: true })
  165 |                   .filter(animation => animation.playState === 'running').length
  166 |             );
  167 |             const widgetAnimations = await frame
  168 |               .locator('body')
  169 |               .evaluate(
  170 |                 () =>
  171 |                   document
  172 |                     .getAnimations()
  173 |                     .filter(animation => animation.playState === 'running')
  174 |                     .length
  175 |               );
  176 |             return hostAnimations + widgetAnimations;
  177 |           })
  178 |           .toBe(0);
  179 |         await expect(holder).toHaveScreenshot(`${scenario}.png`);
  180 | 
  181 |         const accessibility = await new AxeBuilder({ page })
  182 |           .include(['#chatwoot_live_chat_widget', '#app'])
  183 |           .analyze();
  184 |         const axeCounts = {
  185 |           critical: accessibility.violations.filter(
  186 |             violation => violation.impact === 'critical'
  187 |           ).length,
  188 |           serious: accessibility.violations.filter(
  189 |             violation => violation.impact === 'serious'
  190 |           ).length,
  191 |         };
  192 |         const ratio = await computedContrast(anchor);
> 193 |         expect(axeCounts).toEqual(baseline.measurements[scenario].axe);
      |                           ^ Error: expect(received).toEqual(expected) // deep equality
  194 |         expect(ratio).toBeCloseTo(baseline.measurements[scenario].contrast, 2);
  195 | 
  196 |         const geometry = await holder.evaluate(element => {
  197 |           const frameElement = element.querySelector('iframe');
  198 |           const holderRect = element.getBoundingClientRect();
  199 |           const iframeRect = frameElement.getBoundingClientRect();
  200 |           return {
  201 |             gap: Math.round(holderRect.height - iframeRect.height),
  202 |             holderWidth: holderRect.width,
  203 |             iframeWidth: iframeRect.width,
  204 |           };
  205 |         });
  206 | 
  207 |         if (viewportName === 'desktop') {
  208 |           expect(geometry.holderWidth).toBe(400);
  209 |         }
  210 |         if (view === 'unread') {
  211 |           expect(geometry.gap).toBe(4);
  212 |           if (viewportName === 'mobile') {
  213 |             expect(geometry.holderWidth).toBe(316);
  214 |             expect(geometry.iframeWidth).toBe(300);
  215 |           }
  216 |         }
  217 |       });
  218 |     });
  219 |   });
  220 | });
  221 | 
  222 | test('carrega SDK, entrypoint e host reais nas portas contratadas', async ({
  223 |   page,
  224 | }) => {
  225 |   await freezeTime(page);
  226 |   await page.goto(`${HOST_URL}/?scenario=home&theme=light`, {
  227 |     waitUntil: 'domcontentloaded',
  228 |   });
  229 |   await expect
  230 |     .poll(() => page.evaluate(() => window.$chatwoot?.hasLoaded === true), {
  231 |       timeout: 30000,
  232 |     })
  233 |     .toBe(true);
  234 | 
  235 |   const resources = await page.evaluate(() =>
  236 |     performance.getEntriesByType('resource').map(entry => entry.name)
  237 |   );
  238 |   expect(resources).toContain(`${SDK_URL}/app/javascript/entrypoints/sdk.js`);
  239 |   expect(new URL(page.url()).port).toBe('8899');
  240 |   expect(new URL(await page.locator('iframe').getAttribute('src')).origin).toBe(
  241 |     WIDGET_URL
  242 |   );
  243 |   const snippetIsAfterContent = await page
  244 |     .locator('#chatwoot-snippet')
  245 |     .evaluate(snippet => {
  246 |       const siblings = [...snippet.parentElement.children];
  247 |       return (
  248 |         siblings.indexOf(document.querySelector('main')) <
  249 |         siblings.indexOf(snippet)
  250 |       );
  251 |     });
  252 |   expect(snippetIsAfterContent).toBe(true);
  253 | });
  254 | 
  255 | test('congela o relógio e alimenta o store determinístico', async ({
  256 |   page,
  257 | }) => {
  258 |   const { frame } = await prepareScenario(page, 'messages', 'light', 'desktop');
  259 |   const state = await frame.locator('body').evaluate(() => ({
  260 |     ids: Object.keys(
  261 |       window.WOOT_WIDGET.$store.state.conversation.conversations
  262 |     ),
  263 |     now: new Date().toISOString(),
  264 |   }));
  265 |   expect(state.ids).toEqual(['101', '102', '103', '104']);
  266 |   expect(state.now).toBe(FROZEN_TIME);
  267 | });
  268 | 
  269 | test('preserva a geometria original do unread no resize real', async ({
  270 |   page,
  271 | }) => {
  272 |   await prepareScenario(page, 'unread', 'light', 'desktop');
  273 |   await page.setViewportSize(viewports.mobile);
  274 | 
  275 |   await expect
  276 |     .poll(async () => {
  277 |       const geometry = await page
  278 |         .locator('#cw-widget-holder')
  279 |         .evaluate(element => {
  280 |           const frameElement = element.querySelector('iframe');
  281 |           const holderRect = element.getBoundingClientRect();
  282 |           const iframeRect = frameElement.getBoundingClientRect();
  283 |           return {
  284 |             gap: Math.round(holderRect.height - iframeRect.height),
  285 |             holder: Math.round(holderRect.width),
  286 |             iframe: Math.round(iframeRect.width),
  287 |             iframeHeight: Math.round(iframeRect.height),
  288 |           };
  289 |         });
  290 |       return geometry;
  291 |     })
  292 |     .toEqual({
  293 |       gap: 4,
```