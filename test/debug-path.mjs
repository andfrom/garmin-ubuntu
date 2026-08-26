// Drive "Run App" (F5) in the running garmin-theia container headlessly and report what
// happened. Usage: node debug-path.mjs <workspace-name> [port]   (see debug-path.sh)
import puppeteer from 'puppeteer-core';
import { chromePath } from './lib-chrome.mjs';
import fs from 'fs';
const ws = process.argv[2]; const port = process.argv[3] || '3000';
if (!ws) { console.error('usage: node debug-path.mjs <workspace-name> [port]'); process.exit(2); }
fs.mkdirSync('out', { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const b = await puppeteer.launch({ executablePath: chromePath(), headless: 'new', args: ['--no-sandbox', '--disable-gpu', '--window-size=1600,1000'] });
const p = await b.newPage(); await p.setViewport({ width: 1600, height: 1000 });
await p.goto(`http://127.0.0.1:${port}/#/home/theia/workspaces/${ws}`, { waitUntil: 'load', timeout: 60000 });
await p.waitForSelector('#theia-app-shell', { timeout: 60000 });
await sleep(parseInt(process.env.ACTIVATE_WAIT || '30000'));      // plugin host + extension activation
await p.keyboard.press('Escape'); await p.click('#theia-app-shell'); await p.keyboard.press('F5');
try {                                                              // device picker, if launch.json asks for one
  await p.waitForSelector('.quick-input-widget:not([style*="display: none"]) .quick-input-list', { timeout: 15000 });
  await sleep(1000); await p.keyboard.press('Enter');
} catch {}
await sleep(parseInt(process.env.RUN_WAIT || '75000'));            // build + simulator + adapter
await p.screenshot({ path: 'out/debug-path.png' });
const running = await p.$$eval('.theia-debug-thread, .debug-threads .theia-TreeNode', (els) => els.map((e) => e.textContent.trim()).join(' | ')).catch(() => '');
console.log(JSON.stringify({ debugView: running }));
await b.close();
