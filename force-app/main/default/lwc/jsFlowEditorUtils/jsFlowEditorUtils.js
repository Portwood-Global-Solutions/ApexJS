export function inputValue(inputs, name) {
  return (inputs || []).find((row) => row.name === name)?.value ?? '';
}
export function emitInput(component, name, value, dataType = 'String') {
  component.dispatchEvent(
    new CustomEvent(
      value === ''
        ? 'configuration_editor_input_value_deleted'
        : 'configuration_editor_input_value_changed',
      {
        bubbles: true,
        composed: true,
        detail: value === '' ? { name } : { name, newValue: value, newValueDataType: dataType },
      },
    ),
  );
}
export function emitType(component, name, value) {
  component.dispatchEvent(
    new CustomEvent('configuration_editor_generic_type_mapping_changed', {
      bubbles: true,
      composed: true,
      detail: { typeName: name, typeValue: value },
    }),
  );
}
export function dataResources(context) {
  const values = new Map(),
    kinds = {
      SObject: 'Records',
      String: 'Text',
      Number: 'Number',
      Currency: 'Number',
      Boolean: 'Boolean',
      Date: 'Date',
      DateTime: 'DateTime',
    };
  const add = (name, label, type, isCollection, objectType) => {
    const kind = kinds[type];
    if (!kind) return;
    const description =
      kind === 'Records'
        ? (objectType || 'Record') + (isCollection ? ' records' : ' record')
        : kind + (isCollection ? ' collection' : '');
    values.set(name, {
      value: name,
      label: (label || name) + ' (' + description + ')',
      kind,
      isCollection: !!isCollection,
      objectType,
    });
  };
  for (const row of context?.variables || [])
    add(row.name, row.name, row.dataType, row.isCollection, row.objectType);
  for (const row of context?.recordLookups || [])
    if (row.object)
      add(row.name, row.label, 'SObject', row.getFirstRecordOnly === false, row.object);
  for (const row of [
    ...(context?.constants || []),
    ...(context?.formulas || []),
    ...(context?.transforms || []),
  ])
    add(row.name, row.label || row.name, row.dataType, row.isCollection, row.objectType);
  for (const row of context?.actionCalls || []) {
    if (row.actionName === 'JsResultAction' || row.actionName?.endsWith('.JsResultAction')) {
      const objectType = row.dataTypeMappings?.find(
        (item) => item.typeName === 'U__records',
      )?.typeValue;
      for (const [field, type, collection] of [
        ['textValue', 'String', false],
        ['numberValue', 'Number', false],
        ['booleanValue', 'Boolean', false],
        ['dateValue', 'Date', false],
        ['dateTimeValue', 'DateTime', false],
        ['textValues', 'String', true],
        ['numberValues', 'Number', true],
        ['booleanValues', 'Boolean', true],
        ['dateValues', 'Date', true],
        ['dateTimeValues', 'DateTime', true],
        ['records', 'SObject', true],
      ])
        add(
          row.name + '.' + field,
          (row.label || row.name) + ' → ' + field,
          type,
          collection,
          objectType,
        );
    }
  }
  return [...values.values()].sort((a, b) => a.label.localeCompare(b.label));
}
export function resultResources(context) {
  const values = new Map();
  for (const row of context?.textTemplates || [])
    if (row.isViewedAsPlainText)
      values.set(row.name, { label: row.name + ' (plain text template)', value: row.name });
  for (const row of [
    ...(context?.variables || []),
    ...(context?.constants || []),
    ...(context?.formulas || []),
  ])
    if (row.dataType === 'String' && !row.isCollection)
      values.set(row.name, { label: row.name, value: row.name });
  for (const row of context?.actionCalls || [])
    if (
      ['JsCollectionScriptAction', 'JsPortwoodDataAction'].some(
        (name) => row.actionName === name || row.actionName?.endsWith('.' + name),
      )
    )
      values.set(row.name + '.resultJson', {
        label: (row.label || row.name) + ' → resultJson',
        value: row.name + '.resultJson',
      });
  return [...values.values()];
}
