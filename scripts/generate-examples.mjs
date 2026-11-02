import { mkdirSync, writeFileSync } from 'node:fs';
const directory = 'examples/main/default/flows';
mkdirSync(directory, { recursive: true });
const esc = (value) =>
  String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
// XML text wrapping must not introduce a JavaScript line break after return.
const cdata = (value) => `<![CDATA[${String(value).replaceAll(']]>', ']]]]><![CDATA[>')}]]>`;
const param = (name, value) =>
  `<inputParameters><name>${name}</name><value>${value}</value></inputParameters>`;
const ref = (value) => `<elementReference>${value}</elementReference>`;
const variable = (name, type, collection = false, object, input = false, output = false, value) =>
  `<variables><name>${name}</name><dataType>${type}</dataType><isCollection>${collection}</isCollection><isInput>${input}</isInput><isOutput>${output}</isOutput>${object ? `<objectType>${object}</objectType>` : ''}${type === 'Number' ? '<scale>6</scale>' : ''}${value === undefined ? '' : `<value><stringValue>${esc(value)}</stringValue></value>`}</variables>`;
const assignment = (name, items) =>
  `<assignments><name>${name}</name><label>${name.replaceAll('_', ' ')}</label><locationX>176</locationX><locationY>800</locationY>${items.map(([target, source]) => `<assignmentItems><assignToReference>${target}</assignToReference><operator>Assign</operator><value>${ref(source)}</value></assignmentItems>`).join('')}</assignments>`;
const call = (name, action, inputs, next, mapping = '') =>
  `<actionCalls><name>${name}</name><label>${name.replaceAll('_', ' ')}</label><locationX>176</locationX><locationY>200</locationY><actionName>${action}</actionName><actionType>apex</actionType><connector><targetReference>${next}</targetReference></connector>${mapping}<faultConnector><targetReference>Fault</targetReference></faultConnector><flowTransactionModel>CurrentTransaction</flowTransactionModel>${inputs}<storeOutputAutomatically>true</storeOutputAutomatically></actionCalls>`;
const check = (name, action, next) =>
  `<decisions><name>${name}</name><label>Check ${action}</label><locationX>176</locationX><locationY>300</locationY><defaultConnector><targetReference>Error_${action}</targetReference></defaultConnector><defaultConnectorLabel>Failed</defaultConnectorLabel><rules><name>Success_${action}</name><conditionLogic>and</conditionLogic><conditions><leftValueReference>${action}.success</leftValueReference><operator>EqualTo</operator><rightValue><booleanValue>true</booleanValue></rightValue></conditions><connector><targetReference>${next}</targetReference></connector><label>Success</label></rules></decisions>`;
const wrap = (
  name,
  actions,
  assignments,
  decisions,
  variables,
  start = 'Calculate',
  lookups = '',
  templates = '',
) => `<?xml version="1.0" encoding="UTF-8"?>
<Flow xmlns="http://soap.sforce.com/2006/04/metadata">${actions}<apiVersion>68.0</apiVersion>${assignments}${decisions}<environments>Default</environments><interviewLabel>${name}</interviewLabel><label>${name.replaceAll('_', ' ')}</label><processMetadataValues><name>BuilderType</name><value><stringValue>LightningFlowBuilder</stringValue></value></processMetadataValues><processMetadataValues><name>CanvasMode</name><value><stringValue>AUTO_LAYOUT_CANVAS</stringValue></value></processMetadataValues><processType>AutoLaunchedFlow</processType>${lookups}<start><locationX>50</locationX><locationY>0</locationY><connector><targetReference>${start}</targetReference></connector></start><status>Active</status>${templates}${variables}</Flow>`;
const outputs =
  variable('success', 'Boolean', false, null, false, true) +
  variable('error', 'String', false, null, false, true) +
  variable('resultJson', 'String', false, null, false, true) +
  variable('jsonData', 'String', false, null, false, true) +
  variable('total', 'Number', false, null, false, true) +
  variable('datesOut', 'Date', true, null, false, true) +
  variable('timesOut', 'DateTime', true, null, false, true) +
  variable('recordsOut', 'SObject', true, 'Opportunity', false, true);
const inputs =
  variable('accounts', 'SObject', true, 'Account', true) +
  variable('opportunities', 'SObject', true, 'Opportunity', true) +
  variable('amounts', 'Number', true, null, true) +
  variable('dates', 'Date', true, null, true) +
  variable('times', 'DateTime', true, null, true) +
  variable('title', 'String', false, null, true, false, 'ApexJS example');
const rows = [
  { name: 'Customers', kind: 'Records', isCollection: true, records: '{!accounts}' },
  { name: 'Orders', kind: 'Records', isCollection: true, records: '{!opportunities}' },
  ...['Amounts', 'DueDates', 'Times', 'Title'].map((name, i) => ({
    name,
    kind: ['Number', 'Date', 'DateTime', 'Text'][i],
    isCollection: i < 3,
    resource: ['amounts', 'dates', 'times', 'title'][i],
  })),
];
const named =
  param('dataMode', '<stringValue>Direct</stringValue>') +
  param('namedInputs', '<apexValue>' + JSON.stringify(rows) + '</apexValue>');
const lane = (name, source, tag, boundary) =>
  param(
    name,
    `<collectionElements>${ref(source)}</collectionElements><collectionElements><${tag}>${boundary}</${tag}></collectionElements>`,
  );
const sizes = param(
  'inputSizes',
  '<transform><apexClass>JsFlowInputSizes</apexClass><dataType>Apex</dataType><isCollection>false</isCollection><transformValues>' +
    ['amounts', 'dates', 'times']
      .map(
        (source, i) =>
          `<transformValueActions><inputParameters><name>aggregationValues</name><value>${ref(source)}</value></inputParameters><outputFieldApiName>sizes[${i}]</outputFieldApiName><transformType>Count</transformType></transformValueActions>`,
      )
      .join('') +
    '</transformValues></transform>',
);
const native =
  named +
  lane('nativeNumbers', 'amounts', 'numberValue', '0') +
  lane('nativeDates', 'dates', 'dateValue', '1900-01-01') +
  lane('nativeDateTimes', 'times', 'dateTimeValue', '1900-01-01T00:00:00.000Z') +
  lane('nativeTexts', 'title', 'stringValue', '__js_flow_boundary__') +
  sizes;
const libraries = param(
  'libraries',
  '<apexValue>[{"name":"Tools","resource":"ApexJSExampleTools"}]</apexValue>',
);
const source =
  'return {Summary:{Total:libraries.Tools.sum(input.Amounts),CustomerCount:input.Customers.length},Rows:input.Orders,Dates:input.DueDates,Times:input.Times,Title:input.Title};';
const template = `<textTemplates><name>CalculationBody</name><isViewedAsPlainText>true</isViewedAsPlainText><text>${cdata(source)}</text></textTemplates>`;
const readers = [
  ['Read_total', 'Summary.Total', 'Number', 'total', 'numberValue'],
  ['Read_dates', 'Dates', 'DateCollection', 'datesOut', 'dateValues'],
  ['Read_times', 'Times', 'DateTimeCollection', 'timesOut', 'dateTimeValues'],
  ['Read_records', 'Rows', 'Records', 'recordsOut', 'records'],
];
let actions = call(
  'Calculate',
  'JsCollectionScriptAction',
  native + libraries + param('source', ref('CalculationBody')),
  'Check_Calculate',
);
let decisions = check('Check_Calculate', 'Calculate', readers[0][0]);
let assignments =
  assignment('Fault', [['error', '$Flow.FaultMessage']]) +
  assignment('Error_Calculate', [['error', 'Calculate.error']]);
readers.forEach(([name, path, type], i) => {
  actions += call(
    name,
    'JsResultAction',
    param('resultJson', ref('Calculate.resultJson')) +
      param('path', '<stringValue>' + path + '</stringValue>') +
      param('outputType', '<stringValue>' + type + '</stringValue>') +
      (type === 'Records' ? param('objectApiName', '<stringValue>Opportunity</stringValue>') : ''),
    'Check_' + name,
    '<dataTypeMappings><typeName>U__records</typeName><typeValue>Opportunity</typeValue></dataTypeMappings>',
  );
  decisions += check('Check_' + name, name, readers[i + 1]?.[0] || 'Return_result');
  assignments += assignment('Error_' + name, [['error', name + '.error']]);
});
assignments += assignment('Return_result', [
  ['success', 'Calculate.success'],
  ['resultJson', 'Calculate.resultJson'],
  ...readers.map(([name, , , target, field]) => [target, name + '.' + field]),
]);
writeFileSync(
  directory + '/ApexJS_Example_Calculation.flow-meta.xml',
  wrap(
    'ApexJS_Example_Calculation',
    actions,
    assignments,
    decisions,
    inputs + outputs,
    'Calculate',
    '',
    template,
  ),
);
const prepared = call('Prepare', 'JsPortwoodDataAction', native, 'Check_Prepare');
writeFileSync(
  directory + '/ApexJS_Example_Portwood.flow-meta.xml',
  wrap(
    'ApexJS_Example_Portwood',
    prepared,
    assignment('Fault', [['error', '$Flow.FaultMessage']]) +
      assignment('Error_Prepare', [['error', 'Prepare.error']]) +
      assignment('Return_result', [
        ['success', 'Prepare.success'],
        ['resultJson', 'Prepare.resultJson'],
        ['jsonData', 'Prepare.jsonData'],
      ]),
    check('Check_Prepare', 'Prepare', 'Return_result'),
    inputs + outputs,
    'Prepare',
  ),
);
const lookup = (name, object, next, fields) =>
  `<recordLookups><name>${name}</name><label>${name.replaceAll('_', ' ')}</label><locationX>176</locationX><locationY>100</locationY><assignNullValuesIfNoRecordsFound>false</assignNullValuesIfNoRecordsFound><connector><targetReference>${next}</targetReference></connector><filterLogic>and</filterLogic><filters><field>Name</field><operator>EqualTo</operator><value>${ref('fixtureName')}</value></filters><getFirstRecordOnly>false</getFirstRecordOnly><object>${object}</object>${fields.map((field) => '<queriedFields>' + field + '</queriedFields>').join('')}<storeOutputAutomatically>true</storeOutputAutomatically></recordLookups>`;
const recordRows = [
  { name: 'Customers', kind: 'Records', isCollection: true, records: '{!Get_Customers}' },
  { name: 'Orders', kind: 'Records', isCollection: true, records: '{!Get_Orders}' },
];
const recordSource =
  'return {Summary:{Total:libraries.Tools.sum(input.Orders.map(function(row){return row.Amount;})),CustomerName:input.Customers[0].Name}};';
writeFileSync(
  directory + '/ApexJS_Example_Records.flow-meta.xml',
  wrap(
    'ApexJS_Example_Records',
    call(
      'Calculate',
      'JsCollectionScriptAction',
      param('namedInputs', '<apexValue>' + JSON.stringify(recordRows) + '</apexValue>') +
        libraries +
        param('source', '<stringValue>' + cdata(recordSource) + '</stringValue>'),
      'Check_Calculate',
    ),
    assignment('Fault', [['error', '$Flow.FaultMessage']]) +
      assignment('Error_Calculate', [['error', 'Calculate.error']]) +
      assignment('Return_result', [
        ['success', 'Calculate.success'],
        ['resultJson', 'Calculate.resultJson'],
      ]),
    check('Check_Calculate', 'Calculate', 'Return_result'),
    outputs + variable('fixtureName', 'String', false, null, true),
    'Get_Customers',
    lookup('Get_Customers', 'Account', 'Get_Orders', ['Id', 'Name', 'AnnualRevenue']) +
      lookup('Get_Orders', 'Opportunity', 'Calculate', ['Id', 'Name', 'AccountId', 'Amount']),
  ),
);
console.log('Generated three example Flows');
