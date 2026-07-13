import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../precificador.html', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../supabase-protocolos-idempotencia.sql', import.meta.url), 'utf8');
const salvar = html.slice(
  html.indexOf('async function salvarProtocoloLocal()'),
  html.indexOf('// ══ PACIENTES', html.indexOf('async function salvarProtocoloLocal()')),
);

const tests = [
  ['botão de salvar possui identificador estável', () => assert.match(html, /id="save-protocolo-btn"/)],
  ['segunda chamada simultânea é bloqueada', () => assert.match(salvar, /if\(protocoloSaveInFlight\)return/)],
  ['botão fica desabilitado durante a requisição', () => assert.match(salvar, /saveBtn\.disabled=true/)],
  ['trava é liberada em finally', () => assert.match(salvar, /finally[\s\S]*protocoloSaveInFlight=false/)],
  ['mesmo conteúdo reaproveita a chave', () => assert.match(salvar, /saveSignature!==protocoloSaveSignature[\s\S]*protocoloSaveKey=novaChaveProtocolo/)],
  ['persistência usa upsert pela chave', () => assert.match(salvar, /\.upsert\(payload,\{onConflict:'idempotency_key'\}\)/)],
  ['histórico local não recebe o mesmo protocolo duas vezes', () => assert.match(salvar, /historico\.findIndex[\s\S]*historicoIdx>=0/)],
  ['migração adiciona chave UUID', () => assert.match(migration, /add column if not exists idempotency_key uuid/)],
  ['banco possui índice único de idempotência', () => assert.match(migration, /create unique index if not exists protocolos_idempotency_key_uidx/)],
];

for (const [name, run] of tests) {
  run();
  console.log(`PASS ${name}`);
}

console.log(`\n${tests.length}/${tests.length} testes passaram.`);
