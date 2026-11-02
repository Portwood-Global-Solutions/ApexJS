import { LightningElement, api } from 'lwc';
import { dataResources } from 'c/jsFlowEditorUtils';
const COLLECTION_FIELDS = {
  Records: 'records',
  Text: 'texts',
  Number: 'numbers',
  Boolean: 'booleans',
  Date: 'dates',
  DateTime: 'dateTimes',
  JSON: 'valueJson',
};
const VALUE_FIELDS = {
  Records: 'recordValue',
  Text: 'textValue',
  Number: 'numberValue',
  Boolean: 'booleanValue',
};
const reference = (value) =>
  typeof value === 'string' ? value.match(/^\{!([^}]+)\}$/)?.[1] : undefined;
export default class JsNamedCollectionInputs extends LightningElement {
  @api builderContext;
  @api elementInfo;
  rows = [];
  nextId = 0;
  _value;
  lastEmitted;
  @api get value() {
    return this._value;
  }
  set value(value) {
    this._value = value;
    if (value === this.lastEmitted) return;
    try {
      const inputs =
        typeof value === 'string' && value ? JSON.parse(value) : Array.isArray(value) ? value : [];
      this.rows = inputs.map((input) => {
        const kind =
          input.kind ||
          Object.keys(COLLECTION_FIELDS).find((key) => input[COLLECTION_FIELDS[key]] != null) ||
          'Text';
        const isCollection = input.isCollection !== false,
          stored = input[isCollection ? COLLECTION_FIELDS[kind] : VALUE_FIELDS[kind]],
          resource = reference(stored);
        const literal = input.isLiteral ? JSON.parse(input.valueJson) : stored;
        return {
          id: String(this.nextId++),
          name: input.name || '',
          kind,
          isCollection,
          resource: resource || input.resource || '',
          source: resource || input.resource ? 'resource' : 'value',
          literal: literal ?? (kind === 'Boolean' ? false : ''),
          legacy: kind === 'JSON' || (isCollection && !resource && !input.resource),
        };
      });
    } catch {
      this.rows = [];
    }
  }
  get resources() {
    return dataResources(this.builderContext);
  }
  get resourceOptions() {
    return this.resources.map(({ label, value }) => ({ label, value }));
  }
  get sourceOptions() {
    return [
      { label: 'Flow resource', value: 'resource' },
      { label: 'Enter a value', value: 'value' },
    ];
  }
  get valueTypes() {
    return [
      { label: 'Text', value: 'Text' },
      { label: 'Number', value: 'Number' },
      { label: 'Checkbox', value: 'Boolean' },
      { label: 'Date', value: 'Date' },
      { label: 'Date and time', value: 'DateTime' },
    ];
  }
  get inputRows() {
    return this.rows.map((row, index) => {
      const resource = this.resources.find((item) => item.value === row.resource);
      return {
        ...row,
        title: 'Data ' + (index + 1),
        removeLabel: 'Remove data ' + (index + 1),
        isResource: row.source === 'resource',
        isCheckbox: row.kind === 'Boolean',
        inputType: { Number: 'number', Date: 'date', DateTime: 'datetime' }[row.kind] || 'text',
        description: resource
          ? (resource.isCollection ? 'Collection' : 'Single value') +
            (resource.objectType ? ' · ' + resource.objectType : '')
          : '',
        legacyMessage:
          'Choose a Flow resource or enter a single value to replace this older input configuration.',
      };
    });
  }
  handleAdd() {
    this.rows = [
      ...this.rows,
      {
        id: String(this.nextId++),
        name: '',
        kind: 'Text',
        isCollection: false,
        resource: '',
        source: 'resource',
        literal: '',
        legacy: false,
      },
    ];
    this.publish();
  }
  handleRemove(event) {
    this.rows = this.rows.filter((row) => row.id !== event.currentTarget.dataset.id);
    this.publish();
  }
  handleField(event) {
    const id = event.target.dataset.id,
      field = event.target.dataset.field;
    const value =
      field === 'literal' && event.target.type === 'checkbox'
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
    this.rows = this.rows.map((row) => {
      if (row.id !== id) return row;
      if (field === 'source')
        return {
          ...row,
          source: value,
          resource: '',
          kind: 'Text',
          isCollection: false,
          literal: '',
          legacy: false,
        };
      if (field === 'resource') {
        const resource = this.resources.find((item) => item.value === value);
        return {
          ...row,
          resource: value,
          kind: resource?.kind || row.kind,
          isCollection: !!resource?.isCollection,
          legacy: false,
        };
      }
      if (field === 'kind')
        return {
          ...row,
          kind: value,
          isCollection: false,
          literal: value === 'Boolean' ? false : '',
          legacy: false,
        };
      return { ...row, [field]: value };
    });
    this.publish();
  }
  publish() {
    const channels = {
        nativeTexts: [],
        nativeNumbers: [],
        nativeBooleans: [],
        nativeDates: [],
        nativeDateTimes: [],
      },
      actions = [];
    const laneNames = {
      Text: 'nativeTexts',
      Number: 'nativeNumbers',
      Boolean: 'nativeBooleans',
      Date: 'nativeDates',
      DateTime: 'nativeDateTimes',
    };
    const boundaries = {
        Text: '__js_flow_boundary__',
        Number: 0,
        Boolean: false,
        Date: '1900-01-01',
        DateTime: '1900-01-01T00:00:00.000Z',
      },
      dataTypes = {
        Text: 'String',
        Number: 'Number',
        Boolean: 'Boolean',
        Date: 'Date',
        DateTime: 'DateTime',
      };
    const values = this.rows.map((row) => {
      const value = { name: row.name, kind: row.kind, isCollection: row.isCollection };
      const field = row.isCollection ? COLLECTION_FIELDS[row.kind] : VALUE_FIELDS[row.kind];
      if (row.source === 'value') {
        value.isLiteral = true;
        const literal =
          row.kind === 'Number' ? (row.literal === '' ? null : Number(row.literal)) : row.literal;
        // Keep literal text containing merge syntax literal when Flow reads the structured value.
        value.valueJson = JSON.stringify(literal)
          .replaceAll('{', '\\u007b')
          .replaceAll('}', '\\u007d');
      }
      if (
        ['Date', 'DateTime'].includes(row.kind) ||
        (row.source === 'resource' && row.kind !== 'Records')
      ) {
        if (row.resource) value.resource = row.resource;
        if (row.source === 'resource' && row.isCollection)
          actions.push({
            transformType: 'Count',
            outputFieldApiName: 'sizes[' + actions.length + ']',
            inputParameters: [
              { name: 'aggregationValues', value: { elementReference: row.resource } },
            ],
          });
        const lane = channels[laneNames[row.kind]];
        lane.push(
          row.source === 'resource'
            ? { value: row.resource, valueDataType: 'reference' }
            : { value: row.literal, valueDataType: dataTypes[row.kind] },
        );
        lane.push({ value: boundaries[row.kind], valueDataType: dataTypes[row.kind] });
      } else if (row.source === 'resource' && row.resource && field)
        value[field] = '{!' + row.resource + '}';
      return value;
    });
    const inputSizes = actions.length
      ? {
          isCollection: false,
          dataType: 'Apex',
          apexClass: 'JsFlowInputSizes',
          transformValues: [{ transformValueActions: actions }],
        }
      : null;
    this.lastEmitted = JSON.stringify(values);
    this.dispatchEvent(
      new CustomEvent('inputschange', {
        detail: { value: this.lastEmitted, ...channels, inputSizes },
      }),
    );
  }
  @api validate() {
    const errors = [],
      seen = new Set();
    for (const row of this.rows) {
      if (
        !/^[A-Za-z][A-Za-z0-9_]*$/.test(row.name) ||
        ['constructor', 'prototype'].includes(row.name)
      )
        errors.push({
          key: row.id + 'name',
          errorString:
            'Enter a name starting with a letter. Use letters, numbers, or underscores; no spaces.',
        });
      if (seen.has(row.name))
        errors.push({
          key: row.id + 'duplicate',
          errorString: 'Give each data entry a different name.',
        });
      seen.add(row.name);
      if (row.legacy)
        errors.push({
          key: row.id + 'legacy',
          errorString: 'Choose a Flow resource or enter a single value for this data entry.',
        });
      if (row.source === 'resource' && !this.resources.some((item) => item.value === row.resource))
        errors.push({
          key: row.id + 'resource',
          errorString: 'Choose an available Flow resource.',
        });
      if (
        row.source === 'value' &&
        row.kind === 'Number' &&
        (row.literal === '' || !Number.isFinite(Number(row.literal)))
      )
        errors.push({ key: row.id + 'number', errorString: 'Enter a number.' });
      if (
        row.source === 'value' &&
        ['Date', 'DateTime'].includes(row.kind) &&
        (!row.literal || !Number.isFinite(Date.parse(row.literal)))
      )
        errors.push({ key: row.id + 'date', errorString: 'Choose a date.' });
    }
    for (const field of this.template.querySelectorAll('lightning-input,lightning-combobox'))
      field.reportValidity();
    return errors;
  }
}
