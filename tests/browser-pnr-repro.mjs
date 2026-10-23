import { chromium } from 'playwright';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const cases = [
  ['reference_example2', 'PRODUCTION_GRADE/TESTS/example2'],
  ['failing_blink', 'PRODUCTION_GRADE/DEFAULTS/04_blink'],
  ['failing_chaser', 'PRODUCTION_GRADE/DEFAULTS/08_led_chaser'],
];
await mkdir('pnr-repro-output', { recursive: true });
const browser = await chromium.launch({headless:true, args:['--disable-dev-shm-usage']});
let failed = false;
try {
  for (const [name, root] of cases) {
    const page = await browser.newPage();
    const errors = [];
    const browserConsole = [];
    page.on('console', m => { browserConsole.push('['+m.type()+'] '+m.text()); if (m.type()==='error') errors.push(m.text()); });
    page.on('pageerror', e => errors.push(String(e)));
    const verilog = await readFile(resolve(root,'top.v'),'utf8');
    const xdc = await readFile(resolve(root,'top.xdc'),'utf8');
    try {
      await page.goto('http://127.0.0.1:8767/FINAL/index.html', {waitUntil:'domcontentloaded',timeout:60000});
      await page.locator('#code-verilog').fill(verilog);
      await page.locator('#code-xdc').fill(xdc);
      await page.locator('#btn-build').click();
      await page.waitForFunction(() => {
        const t=document.querySelector('#build-stage')?.textContent;
        return t==='Complete'||t==='Build failed';
      }, null, {timeout:240000});
      const stage = await page.locator('#build-stage').innerText();
      const flashEnabled = await page.locator('#btn-flash').isEnabled();
      const log = await page.evaluate(() => document.querySelector('#log').innerText);
      await writeFile('pnr-repro-output/'+name+'.log',browserConsole.join('\n')+'\nVISIBLE TAIL:\n'+log+'\nPAGE ERRORS:\n'+errors.join('\n'));
      await writeFile('pnr-repro-output/'+name+'.json',JSON.stringify({name,root,stage,flashEnabled,errors},null,2));
      console.log(name,stage,'flashEnabled:',flashEnabled,'errors:',errors.slice(-3));
      if (name==='reference_example2' && stage!=='Complete') failed=true;
    } catch(e) {
      failed=true;
      await writeFile('pnr-repro-output/'+name+'.error.txt',String(e)+'\n'+errors.join('\n'));
      console.error(name,e);
    } finally { await page.close(); }
  }
} finally { await browser.close(); }
if(failed)process.exitCode=1;
