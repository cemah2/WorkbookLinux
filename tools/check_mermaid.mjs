// check_mermaid.mjs — valide la syntaxe des blocs ```mermaid des fichiers
// Markdown donnés, avec le même analyseur que GitHub (mermaid 11).
//   npm install --no-save mermaid@11 jsdom
//   node tools/check_mermaid.mjs $(git ls-files '*.md')
import { JSDOM } from 'jsdom';
import fs from 'node:fs';

const dom = new JSDOM('<!doctype html><html><body></body></html>', { pretendToBeVisual: true });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.DOMParser = dom.window.DOMParser;
const { default: mermaid } = await import('mermaid');
mermaid.initialize({ startOnLoad: false });

let blocs = 0, erreurs = 0;
for (const f of process.argv.slice(2)) {
  const texte = fs.readFileSync(f, 'utf8');
  const re = /^```mermaid\n([\s\S]*?)^```/gm;
  let m;
  while ((m = re.exec(texte))) {
    blocs++;
    const ligne = texte.slice(0, m.index).split('\n').length;
    try {
      await mermaid.parse(m[1]);
    } catch (e) {
      erreurs++;
      const msg = String(e.message || e).split('\n').slice(0, 3).join(' | ');
      console.log(`${f}:${ligne} : ${msg}`);
    }
  }
}
console.log(`mermaid : ${blocs} blocs, ${erreurs} en erreur`);
process.exit(erreurs ? 1 : 0);
