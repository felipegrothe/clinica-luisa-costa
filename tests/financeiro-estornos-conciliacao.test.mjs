import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../financeiro.html', import.meta.url), 'utf8');
const sql = readFileSync(new URL('../supabase-financeiro-estornos-conciliacao.sql', import.meta.url), 'utf8');

const tests = [
  ['interface não oferece mais remoção física de lançamento', () => assert.doesNotMatch(html, /onclick="removerLanc\(\)"/)],
  ['estorno exige motivo mínimo', () => assert.match(html, /motivo\.trim\(\)\.length<5/)],
  ['estorno usa RPC transacional', () => assert.match(html, /db\.rpc\('estornar_lancamento_financeiro'/)],
  ['estorno gera chave de idempotência', () => assert.match(html, /crypto\?\.randomUUID/)],
  ['lançamentos estornados ficam fora dos totais', () => assert.match(html, /LANCS=data\.filter\(l=>!l\.estornado_at\)/)],
  ['pagamentos estornados ficam fora do saldo de protocolos', () => assert.match(html, /PAGAMENTOS\.filter\(pg=>!pg\.estornado_at/)],
  ['conciliação exige referência', () => assert.match(html, /referencia\.trim\(\)\.length<3/)],
  ['conciliação usa RPC', () => assert.match(html, /db\.rpc\('conciliar_lancamento_financeiro'/)],
  ['banco preserva lançamento com marca de estorno', () => assert.match(sql, /add column if not exists estornado_at timestamptz/)],
  ['banco impede dois estornos do mesmo lançamento', () => assert.match(sql, /unique\(lancamento_id\)/)],
  ['estorno de pagamento manual reabre saldo', () => assert.match(sql, /v_novo_pago:=greatest\(0,v_pago-v_pag\.valor\)[\s\S]*saldo_devedor=greatest/)],
  ['operações gravam auditoria com estado anterior e posterior', () => assert.match(sql, /insert into public\.fin_auditoria[\s\S]*dados_antes,dados_depois/)],
];

for (const [name, run] of tests) {
  run();
  console.log(`PASS ${name}`);
}
console.log(`\n${tests.length}/${tests.length} testes passaram.`);
