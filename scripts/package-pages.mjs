import {cp,mkdir,writeFile,readdir,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import assert from 'node:assert/strict';
await mkdir('dist',{recursive:true});
for(const name of ['index.html','src','generated','vendor','LICENSE'])await cp(name,join('dist',name),{recursive:true});
await writeFile('dist/.nojekyll','');
// Every relative static import in the shipped compiler/runtime must resolve.
async function check(dir){for(const entry of await readdir(dir,{withFileTypes:true})){
  const path=join(dir,entry.name);if(entry.isDirectory())await check(path);
  else if(entry.name.endsWith('.js')){const text=await readFile(path,'utf8');for(const match of text.matchAll(/(?:from\s*|import\s*)['"](\.[^'"]+)['"]/g))await readFile(join(dir,match[1]));}
}}
await check('dist');
const names=await readdir('dist');assert(names.every(n=>['index.html','src','generated','vendor','LICENSE','.nojekyll'].includes(n)));
console.log('Packaged GitHub Pages site; all relative JavaScript imports resolve.');
