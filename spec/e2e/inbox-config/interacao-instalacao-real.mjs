// Teste de INTERACAO contra a instalacao REAL (hmlchat), nos dois temas.
//
// Diferente dos specs de componente: aqui o navegador clica os CONTROLES DENTRO de cada aba —
// interruptores, radios, seletores — e nao so as abas. Foi assim que apareceram, nesta ordem:
//   · o front chamando /tracking_credentials (plural) contra a rota singular -> 404;
//   · depois do conserto do 404, um 500: a tabela tracking_credentials nao existia no banco
//     desta VM, porque a migration foi integrada e nunca rodada aqui;
//   · e /tracking_deliveries, que segue 404 porque o item 4.14 nao foi construido.
// Nenhum spec de front ou de backend pegava: o do front dubla o HTTP, o do backend chama o
// controller direto. So o encontro dos dois revela.
//
// Uso:  SHOTS=<dir> node spec/e2e/inbox-config/interacao-instalacao-real.mjs
// Usuario dedicado de QA. NUNCA use conta real, NUNCA resete senha de ninguem.
//
// O produto CONFIRMA antes de acao com consequencia ("Sair sem salvar?", "Abrir o painel
// sozinho?"). Isso e comportamento certo — o teste responde aos dialogos escolhendo sempre a
// opcao conservadora. Um teste que tropeca no dialogo mede menos do que parece.
import { chromium } from 'playwright';
import fs from 'fs';

const BASE='https://hmlchat.simplexsolucoes.com.br';
const SHOTS=process.env.SHOTS;
const log=[]; const erros=[];
const P=(...a)=>{ const s=a.join(' '); log.push(s); console.log(s); };


// O produto confirma antes de acoes com consequencia. Isso e CERTO — o teste tem de responder
// aos dialogos, nao tropecar neles. Dois vistos ate agora:
//   "Sair sem salvar?"     -> [Continuar editando] [Sair e descartar]
//   "Abrir o painel sozinho?" -> [Manter o nivel atual] [Ligar mesmo assim]
// Sempre escolhemos a opcao CONSERVADORA, e para navegar escolhemos descartar.
async function fecharDialogos(page, P, tema, ondeVou = false) {
  for (let volta = 0; volta < 4; volta++) {
    const titulo = await page.evaluate(() => {
      const d = document.querySelector('[role="dialog"], .modal');
      return d ? (d.querySelector('h1,h2,h3')?.textContent || '').trim() : null;
    });
    if (!titulo) return volta > 0;
    const conservador = ['manter o nivel atual','manter o nível atual','cancelar','fechar'];
    const paraSair = ['sair e descartar'];
    const nomes = ondeVou ? [...paraSair, ...conservador] : [...conservador, ...paraSair];
    let clicou = false;
    for (const n of nomes) {
      const b = page.getByRole('button', { name: new RegExp(n, 'i') });
      if (await b.count().catch(() => 0)) { await b.first().click({ timeout: 5000 }).catch(() => {}); clicou = true; break; }
    }
    P(`[${tema}] dialogo "${titulo}" -> ${clicou ? 'fechado' : 'NAO SOUBE FECHAR'}`);
    if (!clicou) return false;
    await page.waitForTimeout(1200);
  }
  return true;
}

async function logar(page){
  await page.goto(`${BASE}/app/login`,{waitUntil:'domcontentloaded',timeout:60000});
  await page.fill('input[name="email_address"]','qa-playwright@simplex.test');
  await page.fill('input[type="password"]','QaPlay2026spx!');
  await page.getByRole('button',{name:/entrar/i}).click();
  await page.waitForURL(/\/app\/accounts/,{timeout:60000});
}

async function run(tema){
  const b = await chromium.launch({args:['--no-sandbox']});
  const ctx = await b.newContext({viewport:{width:1440,height:900},colorScheme:tema,ignoreHTTPSErrors:true});
  const page = await ctx.newPage();
  page.on('pageerror',e=>erros.push(`[${tema}] pageerror: ${String(e).slice(0,150)}`));
  page.on('response',r=>{ if(r.status()>=400 && r.url().includes('/api/')) erros.push(`[${tema}] HTTP ${r.status()} ${r.url().split('/api/')[1].slice(0,80)}`); });

  await logar(page);
  const url=`${BASE}/app/accounts/3/settings/inboxes/6`;
  await page.goto(url,{waitUntil:'domcontentloaded',timeout:60000});
  await page.waitForTimeout(4000);

  // 1) ABAS: nomes e transbordo
  const barra = await page.evaluate(()=>{
    const ul=document.querySelector('[role="tablist"], .tabs');
    if(!ul) return null;
    const abas=[...ul.querySelectorAll('[role="tab"], li')].map(a=>(a.textContent||'').trim()).filter(Boolean);
    const fora=[...ul.querySelectorAll('[role="tab"], li')].filter(a=>{
      const x=a.getBoundingClientRect(), u=ul.getBoundingClientRect();
      return x.right>u.right+1 || x.left<u.left-1;
    }).map(a=>(a.textContent||'').trim()).filter(Boolean);
    return { abas:[...new Set(abas)], scrollW:ul.scrollWidth, clientW:ul.clientWidth, fora:[...new Set(fora)] };
  });
  P(`[${tema}] ABAS: ${JSON.stringify(barra.abas)}`);
  P(`[${tema}] transbordo: ${barra.scrollW} vs ${barra.clientW} | fora da vista: ${JSON.stringify(barra.fora)}`);
  const temChevron = await page.evaluate(()=>!!document.querySelector('[role="tablist"] button, .tabs button, [data-testid*="chevron"], [aria-label*="mais"], [aria-label*="Mais"]'));
  P(`[${tema}] tem controle de rolagem/chevron: ${temChevron}`);

  // 2) AVATAR: galeria existe? clicar um e ver o preview mudar
  const antesPrev = await page.evaluate(()=>{
    const p=document.querySelector('[class*="preview"], aside, .widget-preview');
    return (p?.innerText||'').slice(0,120);
  });
  const galeria = await page.$$('[data-testid*="avatar"], [class*="avatar"] button, button[class*="avatar"], img[src*="inbox-avatars"]');
  P(`[${tema}] AVATAR: candidatos de galeria=${galeria.length} | input[type=file]=${await page.$$eval('input[type=file]',e=>e.length)}`);
  let avatarClicado=false;
  const imgs = await page.$$('img[src*="inbox-avatars"]');
  if (imgs.length){
    P(`[${tema}] AVATAR: ${imgs.length} avatares padrao renderizados`);
    try{
      await imgs[1].click({timeout:6000});
      await page.waitForTimeout(2500);
      avatarClicado=true;
      await page.screenshot({path:`${SHOTS}/avatar-${tema}.png`,fullPage:false});
      const depoisPrev = await page.evaluate(()=>{
        const im=[...document.querySelectorAll('img')].map(i=>i.src).filter(s=>s.includes('inbox-avatars'));
        return im.length;
      });
      P(`[${tema}] AVATAR: clicou o 2o | imagens de avatar no DOM depois=${depoisPrev}`);
    }catch(e){ P(`[${tema}] AVATAR: falhou ao clicar — ${String(e).slice(0,80)}`); }
  } else {
    P(`[${tema}] AVATAR: NENHUM avatar padrao renderizado`);
  }

  // 3) CLICAR OS CONTROLES DENTRO DE CADA ABA
  const abasEls = await page.$$('[role="tab"], .tabs-title a');
  for (let i=0;i<abasEls.length;i++){
    const els = await page.$$('[role="tab"], .tabs-title a');
    if(!els[i]) continue;
    const nome=((await els[i].textContent())||'').trim();
    if(!nome) continue;
    await fecharDialogos(page, P, tema, true);
    let ok = true;
    try{ await els[i].click({timeout:8000}); }catch{ ok = false; }
    if (!ok) {
      await fecharDialogos(page, P, tema, true);
      const els3 = await page.$$('[role="tab"], .tabs-title a');
      try{ await els3[i].click({timeout:8000}); }catch{ P(`[${tema}] "${nome}": nao clicou nem apos fechar dialogo`); continue; }
    }
    await page.waitForTimeout(1200);
    // A guarda de alteracoes nao salvas e comportamento CORRETO: ela lista os campos mexidos e
    // bloqueia a navegacao. O teste tem de responder a ela, nao tropecar nela.
    const descartar = page.getByRole('button', { name: /sair e descartar/i });
    if (await descartar.count().catch(()=>0)) {
      const campos = await page.evaluate(()=>[...document.querySelectorAll('[role="dialog"] li, .modal li')].map(l=>(l.textContent||'').trim()).filter(Boolean));
      P(`[${tema}] dialogo "sair sem salvar" apareceu ao deixar a aba anterior; campos: ${JSON.stringify(campos)} -> descartando`);
      await descartar.first().click({timeout:6000}).catch(()=>{});
      await page.waitForTimeout(1500);
      const els2 = await page.$$('[role="tab"], .tabs-title a');
      if (els2[i]) { await els2[i].click({timeout:8000}).catch(()=>{}); await page.waitForTimeout(1500); }
    }
    await page.waitForTimeout(800);
    const antes=erros.length;
    // interruptores
    const toggles = await page.$$('main input[type="checkbox"], main [role="switch"]');
    let mexidos=0;
    for (const t of toggles.slice(0,6)){
      try{ await t.click({timeout:3000}); await page.waitForTimeout(400); await t.click({timeout:3000}); await page.waitForTimeout(300); mexidos++; }catch{}
    }
    // radios
    const radios = await page.$$('main input[type="radio"]');
    let radiosOk=0;
    for (const r of radios.slice(0,4)){ try{ await r.click({timeout:3000}); await page.waitForTimeout(300); radiosOk++; }catch{} }
    // selects
    const selects = await page.$$('main select');
    // botoes que NAO sao destrutivos
    const botoes = await page.$$eval('main button', bs => bs.map(b=>(b.textContent||'').trim()).filter(Boolean).slice(0,10));
    await fecharDialogos(page, P, tema, false);
    P(`[${tema}] "${nome}": toggles=${toggles.length}(mexi ${mexidos}) radios=${radios.length}(${radiosOk}) selects=${selects.length} botoes=${JSON.stringify(botoes.slice(0,5))} | erros novos=${erros.length-antes}`);
    await page.screenshot({path:`${SHOTS}/int-${tema}-${nome.replace(/[^\w]+/g,'_').slice(0,20)}.png`,fullPage:false});
  }
  await b.close();
}

for (const t of ['light','dark']) { try{ await run(t); }catch(e){ erros.push(`[${t}] FATAL: ${String(e).slice(0,180)}`); } }
fs.writeFileSync(`${SHOTS}/interacao.txt`, log.join('\n')+'\n\n=== ERROS ===\n'+(erros.join('\n')||'(nenhum)'));
console.log('\n=== ERROS ==='); console.log(erros.length?erros.join('\n'):'(nenhum)');
