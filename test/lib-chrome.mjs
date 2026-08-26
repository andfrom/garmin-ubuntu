import fs from 'fs';
export function chromePath() {
  const c = [process.env.CHROME, '/snap/bin/chromium', '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable'].filter(Boolean);
  for (const p of c) if (fs.existsSync(p)) return p;
  throw new Error('No Chromium/Chrome found; set CHROME=/path/to/binary');
}
