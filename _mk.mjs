import { chromium } from 'playwright';
const SH='/tmp/claude-1001/-home-chatwoot-chatwoot/d81786a2-f2e5-47e6-ad4f-41caab68b778/scratchpad/shots';
const b=await chromium.launch(); const errs=[];
for (const theme of ['light','dark']) {
  const ctx=await b.newContext({viewport:{width:1240,height:1000},colorScheme:theme});
  const p=await ctx.newPage();
  p.on('pageerror',e=>errs.push(theme+': '+e.message.slice(0,110)));
  p.on('console',m=>{if(m.type()==='error')errs.push(theme+' console: '+m.text().slice(0,110));});
  await p.goto('http://localhost:3000/mockups/copiloto-v2.html',{waitUntil:'domcontentloaded'});
  await p.waitForTimeout(1000);
  await p.click('[data-st="done"]'); await p.waitForTimeout(600);
  await p.locator('.app').first().scrollIntoViewIfNeeded(); await p.waitForTimeout(400);
  await p.screenshot({path:`${SH}/oa-${theme}.png`});
  const use=p.locator('.act.primary').first();
  if(await use.count()){ await use.click(); await p.waitForTimeout(300); }
  console.log(theme,'composer preenchido:', await p.locator('#composerBox.filled').count()>0);
  await ctx.close();
}
console.log('erros JS:', errs.length?errs.slice(0,3).join(' | '):'nenhum');
await b.close();
