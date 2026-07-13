import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../financeiro.html', import.meta.url), 'utf8');
const dashboard = html.slice(html.indexOf('function renderDash()'), html.indexOf('// ── RECEITAS'));
const receitas = html.slice(html.indexOf('function renderReceitas()'), html.indexOf('// ── DESPESAS'));
const despesas = html.slice(html.indexOf('function renderDespesas()'), html.indexOf('// ── PAGINAÇÃO'));
const dre = html.slice(html.indexOf('function renderDRE()'), html.indexOf('function setDreMes'));

const tests = [
  ['nome do mês usa data local ao meio-dia', () => assert.match(html, /new Date\(Number\(match\[1\]\),Number\(match\[2\]\)-1,1,12\)/)],
  ['nome do mês não interpreta YYYY-MM-DD como UTC', () => assert.doesNotMatch(html, /new Date\(m\+'-01'\)/)],
  ['período financeiro aceita apenas prefixo YYYY-MM válido', () => assert.match(html, /const periodoFinanceiro=.*\^\\d\{4\}-\\d\{2\}/)],
  ['KPIs e tabela do dashboard usam o mesmo mês', () => {
    assert.match(dashboard, /periodoFinanceiro\(l\.data\)===mes/);
    assert.doesNotMatch(dashboard, /mesFiltro/);
  }],
  ['dashboard inicia pelo mês atual', () => assert.match(html, /const atual=mes\.value\|\|mesAtual\(\)/)],
  ['lista de meses é preenchida na inicialização', () => assert.match(html, /await carregar\(\);\s*popularMeses\(\);\s*renderDash\(\)/)],
  ['receitas filtram categoria exata e período normalizado', () => {
    assert.match(receitas, /categoriaNoGrupo\(l\.categoria_dre,cat\)/);
    assert.match(receitas, /periodoFinanceiro\(l\.data\)===mes/);
  }],
  ['despesas filtram categoria exata e período normalizado', () => {
    assert.match(despesas, /categoriaNoGrupo\(l\.categoria_dre,cat\)/);
    assert.match(despesas, /periodoFinanceiro\(l\.data\)===mes/);
  }],
  ['DRE usa período financeiro normalizado', () => assert.match(dre, /periodoFinanceiro\(l\.data\)===mes/)],
  ['filtro da auditoria converte timestamp para data local', () => assert.match(html, /const data=dataLocalTimestamp\(a\.created_at\)/)],
  ['não restam filtros mensais baseados em startsWith', () => assert.doesNotMatch(html, /data\?*\.startsWith\(mes/)],
  ['layout usa painéis de filtro consistentes', () => assert.ok((html.match(/class="filter-panel"/g)||[]).length>=3)],
  ['atalhos cobrem mês atual, anterior, 30 dias e todo período', () => {
    for(const chave of ['atual','anterior','30d','todos'])assert.match(html,new RegExp(`q-${chave}`));
  }],
  ['últimos 30 dias inclui hoje e os 29 dias anteriores', () => assert.match(html, /inicio30\.setDate\(inicio30\.getDate\(\)-29\)/)],
  ['alteração manual remove destaque do atalho', () => assert.match(html, /function periodoManual\(prefix\)\{marcarPeriodoAtivo\(prefix,''\);\}/)],
  ['atalhos reiniciam paginação antes de renderizar', () => assert.match(html, /REC_PG=0;renderReceitas[\s\S]*DES_PG=0;renderDespesas[\s\S]*AUD_PG=0;renderAuditoria/)],
];

for (const [name, run] of tests) {
  run();
  console.log(`PASS ${name}`);
}
console.log(`\n${tests.length}/${tests.length} testes passaram.`);
