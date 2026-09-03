import { chromium } from 'playwright';
const b=await chromium.launch(); const ctx=await b.newContext({viewport:{width:1280,height:900}});
const p=await ctx.newPage();
await p.goto('file:///home/chatwoot/chatwoot/plano/redesenho/mockups/10-widget-mobile.html',{waitUntil:'load'});
await p.waitForTimeout(300);
console.log(await p.evaluate(()=>{const h=document.querySelector('.mk-studio__title');
 const c=getComputedStyle(h); return {fs:c.fontSize,fw:c.fontWeight,lh:c.lineHeight};}));
await b.close();
