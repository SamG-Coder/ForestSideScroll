import {readFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
const hash=x=>createHash('sha256').update(x).digest('hex');
const manifest=JSON.parse(await readFile('generated/manifest.json','utf8'));
assert.equal(hash((await Promise.all(manifest.files.map(f=>readFile(`src/${f}.cu`,'utf8')))).join('\n')),manifest.sourceSha256);
for(const entry of manifest.entries){
  assert.equal(hash(await readFile(`generated/${entry.entry}.json`)),entry.sha256);
  assert.equal(hash(await readFile(`generated/${entry.entry}.wgsl`)),entry.wgslSha256);
}
for(const dir of ['src','scripts'])for(const f of await readdir(dir))if(/\.m?js$/.test(f))execFileSync(process.execPath,['--check',`${dir}/${f}`],{stdio:'inherit'});
console.log(`Validated ${manifest.entries.length} CUDA kernels and JavaScript syntax.`);
