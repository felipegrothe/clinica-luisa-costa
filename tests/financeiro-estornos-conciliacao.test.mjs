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
  ['navegação possui página de auditoria', () => assert.match(html, /goSub\('auditoria',this\)/)],
  ['auditoria é carregada diretamente da tabela protegida', () => assert.match(html, /db\.from\('fin_auditoria'\)/)],
  ['consulta de auditoria possui limite defensivo', () => assert.match(html, /\.order\('created_at',\{ascending:false\}\)\.limit\(500\)/)],
  ['tela identifica histórico como somente leitura', () => assert.match(html, /Histórico financeiro imutável[\s\S]*Somente leitura/)],
  ['filtros incluem ação, busca e intervalo', () => {
    assert.match(html, /id="aud-acao"/);assert.match(html, /id="aud-busca"/);assert.match(html, /id="aud-de"/);assert.match(html, /id="aud-ate"/);
  }],
  ['dados vindos da auditoria são escapados na tabela', () => assert.match(html, /function renderRowAuditoria[\s\S]*esc\(antes\.descricao/)],
  ['responsável externo não expõe UUID completo', () => assert.match(html, /slice\(-6\)/)],
  ['lançamento estornado pode ser consultado sem ações administrativas', () => {
    assert.match(html, /\[\.\.\.LANCS,\.\.\.LANCS_ESTORNADOS\]/);
    assert.match(html, /isAdmin\(\)&&!l\.estornado_at/);
  }],
];

for (const [name, run] of tests) {
  run();
  console.log(`PASS ${name}`);
}
console.log(`\n${tests.length}/${tests.length} testes passaram.`);
