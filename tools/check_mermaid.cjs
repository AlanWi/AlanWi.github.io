const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

async function main() {
  const manifest = process.argv[2] || '.jekyll-check/mermaid.json';
  const diagrams = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  if (diagrams.length === 0) {
    console.log('No Mermaid diagrams to check.');
    return;
  }
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {})
  });
  const errors = [];
  try {
    const page = await browser.newPage();
    // Render with the same Mermaid version as the locked Chirpy theme, offline.
    await page.route('**/*', route => route.abort());
    await page.setContent('<!doctype html><html><body></body></html>');
    const mermaid = path.join(path.dirname(require.resolve('mermaid/package.json')), 'dist/mermaid.min.js');
    await page.addScriptTag({ path: mermaid });
    await page.evaluate(() => mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' }));
    for (const [index, diagram] of diagrams.entries()) {
      try {
        await page.evaluate(async ({ code, index }) => {
          const result = await mermaid.render(`check-${index}`, code);
          if (!result.svg.includes('<svg')) throw new Error('No SVG produced');
        }, { code: diagram.code, index });
      } catch (error) {
        errors.push(`${diagram.page}, diagram ${diagram.diagram}: ${error.message}`);
      }
    }
  } finally {
    await browser.close();
  }
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(`Mermaid rendering passed (${diagrams.length} diagrams).`);
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
