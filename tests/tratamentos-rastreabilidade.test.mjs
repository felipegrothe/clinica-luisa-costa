import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../precificador.html',import.meta.url),'utf8');
const sql=readFileSync(new URL('../supabase-tratamentos-rastreabilidade.sql',import.meta.url),'utf8');

const tests=[
  ['setor foi renomeado sem trocar a chave técnica',()=>{assert.match(html,/>Tratamentos</);assert.match(sql,/can_access_module\('precificador'\)/)}],
  ['interface possui planos, aplicação avulsa e histórico',()=>{assert.match(html,/id="pg-planos"/);assert.match(html,/id="pg-aplicacao"/);assert.match(html,/id="pg-historico"/)}],
  ['planos exigem vínculo por UUID ao paciente',()=>assert.match(sql,/paciente_id uuid not null references public\.pacientes\(id\) on delete restrict/)],
  ['aplicações possuem idempotência',()=>{assert.match(sql,/tratamento_aplicacoes_idempotency_uidx/);assert.match(html,/aplicacaoSaveInFlight/)}],
  ['registro de aplicação e baixa de lote são atômicos',()=>{assert.match(sql,/create or replace function public\.registrar_tratamento_aplicacao/);assert.match(sql,/for update/);assert.match(sql,/update public\.lotes set usado_base=usado_base\+v_qtd/);assert.match(sql,/insert into public\.movimentacoes/)}],
  ['lote vencido e saldo insuficiente são bloqueados',()=>{assert.match(sql,/Não é permitido aplicar lote vencido/);assert.match(sql,/Saldo insuficiente no lote/)}],
  ['aplicações confirmadas não recebem delete direto',()=>assert.doesNotMatch(sql,/grant select,\s*insert,\s*update,\s*delete on public\.tratamento_aplicacoes/i)],
  ['gravações clínicas diretas são revogadas',()=>assert.match(sql,/revoke insert,update,delete on public\.tratamento_planos/)],
  ['alterações relevantes geram auditoria',()=>{assert.match(sql,/tratamento_auditoria/);assert.match(sql,/after insert or update on public\.tratamento_aplicacoes/)}],
  ['histórico consolida uma linha por medicamento',()=>{assert.match(sql,/create or replace view public\.tratamento_rastreabilidade/);assert.match(sql,/join public\.tratamento_aplicacao_itens/)}],
  ['histórico oferece relatório PDF e CSV',()=>{assert.match(html,/exportarHistoricoPDF\(\)/);assert.match(html,/exportarHistoricoCSV\(\)/)}],
  ['plano possui PDF próprio para assinatura',()=>{assert.match(html,/pdfPlanoTratamento\('/);assert.match(html,/PLANO DE ACOMPANHAMENTO/);assert.match(html,/Paciente \/ responsável/)}],
  ['aplicação atual e histórica possuem PDF individual',()=>{assert.match(html,/pdfFormularioAplicacao\(\)/);assert.match(html,/pdfAplicacaoHistorica\('/);assert.match(html,/REGISTRO DE APLICAÇÃO/)}],
  ['documentos possuem mapa corporal em branco',()=>{assert.match(html,/MAPA CORPORAL/);assert.match(html,/pdfBoneco/);assert.match(html,/FRENTE/);assert.match(html,/COSTAS/);assert.match(html,/ANOTAÇÕES MANUAIS/)}],
  ['exportação neutraliza fórmulas em CSV',()=>assert.match(html,/if\(\/\^\[=\+\\-@\]\//)],
  ['uso de lote manual é identificado como legado',()=>{assert.match(sql,/manual_legado/);assert.match(html,/Manual \/ legado/)}],
  ['duplo clique é bloqueado nas duas gravações',()=>{assert.match(html,/if\(planoSaveInFlight\)return/);assert.match(html,/if\(aplicacaoSaveInFlight\)return/)}],
  ['sessão realizada não pode ser duplicada no mesmo plano',()=>assert.match(sql,/tratamento_aplicacoes_plano_sessao_realizada_uidx/)]
];

let failures=0;
for(const [name,fn] of tests){try{fn();console.log('PASS',name)}catch(error){failures++;console.error('FAIL',name);console.error(error.message)}}
if(failures)process.exitCode=1;else console.log(`\n${tests.length}/${tests.length} testes de tratamentos passaram.`);
