// Open a Theia URL in headless Chromium and keep the page alive for a while, so the
// backend spawns a plugin host and activates plugins. Usage: node lib-open-theia.mjs <url> [ms]
import puppeteer from 'puppeteer-core';
import { chromePath } from './lib-chrome.mjs';
const url = process.argv[2]; const wait = parseInt(process.argv[3] || '50000');
const b = await puppeteer.launch({ executablePath: chromePath(), headless: 'new', args: ['--no-sandbox', '--disable-gpu'] });
const p = await b.newPage(); await p.goto(url, { waitUntil: 'load', timeout: 60000 });
await p.waitForSelector('#theia-app-shell', { timeout: 60000 }); await new Promise(r => setTimeout(r, wait)); await b.close();
