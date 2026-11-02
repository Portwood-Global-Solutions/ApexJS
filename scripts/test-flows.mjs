import { mkdirSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { sf, targetOrg } from './salesforce.mjs';
const org = targetOrg();
mkdirSync('reports', { recursive: true });
const inventory = sf(['org', 'list']).result;
assert.ok(
  inventory?.scratchOrgs?.some(
    (row) => [row.alias, row.username, row.orgId].includes(org) && row.status === 'Active',
  ),
  'Flow verification creates synthetic data and is restricted to an active scratch org.',
);
const deployed = sf(
  ['project', 'deploy', 'start', '--source-dir', 'examples', '--wait', '30'],
  org,
);
writeFileSync('reports/example-deploy.json', JSON.stringify(deployed, null, 2));
assert.equal(
  deployed.result?.status,
  'Succeeded',
  JSON.stringify(deployed.result?.details?.componentFailures || deployed.message),
);
const code = `
String fixture='ApexJS '+EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0,12);
Account customer=new Account(Name=fixture,AnnualRevenue=123);insert customer;
Opportunity order=new Opportunity(Name=fixture,AccountId=customer.Id,StageName='Prospecting',CloseDate=Date.today(),Amount=456);insert order;
try{
 Map<String,Object> supplied=new Map<String,Object>{'accounts'=>new List<Account>{customer},'opportunities'=>new List<Opportunity>{order},'amounts'=>new List<Decimal>{12.5,29.5},'dates'=>new List<Date>{Date.newInstance(2026,11,1),null},'times'=>new List<Datetime>{Datetime.newInstanceGmt(2026,11,1,8,30,0),Datetime.newInstanceGmt(2026,11,1,9,30,0)}};
 for(String name:new List<String>{'ApexJS_Example_Calculation','ApexJS_Example_Portwood'}){
  Integer writes=Limits.getDmlStatements();Flow.Interview interview=Flow.Interview.createInterview(name,supplied);interview.start();
  System.debug('APEXJS_FLOW='+JSON.serialize(new Map<String,Object>{'flow'=>name,'success'=>interview.getVariableValue('success'),'error'=>interview.getVariableValue('error'),'resultJson'=>interview.getVariableValue('resultJson'),'jsonData'=>interview.getVariableValue('jsonData'),'total'=>interview.getVariableValue('total'),'dates'=>interview.getVariableValue('datesOut'),'times'=>interview.getVariableValue('timesOut'),'records'=>interview.getVariableValue('recordsOut'),'actionDml'=>Limits.getDmlStatements()-writes}));
 }
 Flow.Interview records=Flow.Interview.createInterview('ApexJS_Example_Records',new Map<String,Object>{'fixtureName'=>fixture});records.start();System.debug('APEXJS_FLOW='+JSON.serialize(new Map<String,Object>{'flow'=>'ApexJS_Example_Records','success'=>records.getVariableValue('success'),'error'=>records.getVariableValue('error'),'resultJson'=>records.getVariableValue('resultJson')}));
 Flow.Interview empty=Flow.Interview.createInterview('ApexJS_Example_Calculation',new Map<String,Object>());empty.start();System.debug('APEXJS_EMPTY='+JSON.serialize(new Map<String,Object>{'success'=>empty.getVariableValue('success'),'error'=>empty.getVariableValue('error'),'total'=>empty.getVariableValue('total')}));
}finally{delete order;delete customer;}
`;
writeFileSync('reports/test-flows.apex', code);
const execution = sf(['apex', 'run', '--file', 'reports/test-flows.apex'], org);
writeFileSync('reports/flows-run.json', JSON.stringify(execution, null, 2));
const logs = execution.result?.logs || '';
const rows = logs
  .split('\n')
  .filter((line) => line.includes('|DEBUG|APEXJS_FLOW='))
  .map((line) => JSON.parse(line.split('|DEBUG|APEXJS_FLOW=')[1]));
assert.equal(rows.length, 3, execution.message || 'Missing Flow results.');
for (const row of rows) {
  assert.equal(row.success, true, row.flow + ': ' + row.error);
  if ('actionDml' in row) assert.equal(row.actionDml, 0);
}
const calculation = rows[0];
assert.equal(calculation.total, 42);
assert.deepEqual(
  calculation.dates.map((value) => (value === null ? null : value.substring(0, 10))),
  ['2026-11-01', null],
);
assert.deepEqual(calculation.times, ['2026-11-01T08:30:00.000Z', '2026-11-01T09:30:00.000Z']);
assert.equal(calculation.records[0].Amount, 456);
const prepared = JSON.parse(rows[1].jsonData);
assert.equal(
  prepared.Customers.records[0].Name,
  JSON.parse(rows[2].resultJson).Summary.CustomerName,
);
assert.equal(prepared.Amounts.records[0].Value, 12.5);
assert.equal(JSON.parse(rows[2].resultJson).Summary.Total, 456);
const emptyLine = logs.split('\n').find((line) => line.includes('|DEBUG|APEXJS_EMPTY='));
assert.ok(emptyLine);
const empty = JSON.parse(emptyLine.split('|DEBUG|APEXJS_EMPTY=')[1]);
assert.equal(empty.success, true, empty.error);
assert.equal(empty.total, 0);
writeFileSync(
  'reports/flow-summary.json',
  JSON.stringify(
    {
      passed: true,
      flows: rows.map((row) => row.flow),
      emptyInputs: true,
      nativeDates: true,
      librarySource: true,
      typedOutputs: true,
      zeroActionDml: true,
    },
    null,
    2,
  ) + '\n',
);
console.log(
  'Passed: mixed records, Get Records, native dates, library execution, typed outputs, empty inputs, and Portwood preparation.',
);
