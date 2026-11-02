import { dataResources, resultResources } from 'c/jsFlowEditorUtils';
it('offers mixed record lookups, primitive variables, and typed action outputs', () => {
  const context = {
    variables: [
      { name: 'Days', dataType: 'Date', isCollection: true },
      { name: 'Rate', dataType: 'Number', isCollection: false },
    ],
    recordLookups: [
      { name: 'Accounts', label: 'Get accounts', object: 'Account', getFirstRecordOnly: false },
      { name: 'Orders', object: 'Opportunity', getFirstRecordOnly: false },
    ],
    actionCalls: [
      {
        name: 'Read',
        actionName: 'JsResultAction',
        dataTypeMappings: [{ typeName: 'U__records', typeValue: 'Contact' }],
      },
    ],
  };
  expect(dataResources(context)).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        value: 'Accounts',
        kind: 'Records',
        objectType: 'Account',
        isCollection: true,
      }),
      expect.objectContaining({ value: 'Orders', kind: 'Records', objectType: 'Opportunity' }),
      expect.objectContaining({ value: 'Read.dateValues', kind: 'Date', isCollection: true }),
      expect.objectContaining({ value: 'Read.records', objectType: 'Contact' }),
    ]),
  );
});
it('offers plain text templates and previous result JSON as text resources', () => {
  expect(
    resultResources({
      textTemplates: [
        { name: 'Script', isViewedAsPlainText: true },
        { name: 'Rich', isViewedAsPlainText: false },
      ],
      actionCalls: [{ name: 'Prepare', actionName: 'JsPortwoodDataAction' }],
    }).map((row) => row.value),
  ).toEqual(['Script', 'Prepare.resultJson']);
});
