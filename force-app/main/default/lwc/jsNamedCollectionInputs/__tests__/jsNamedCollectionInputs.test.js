import { createElement } from 'lwc';
import Inputs from 'c/jsNamedCollectionInputs';

const flush = () => Promise.resolve();
const context = {
  variables: [
    { name: 'Accounts', dataType: 'SObject', objectType: 'Account', isCollection: true },
    { name: 'Opportunities', dataType: 'SObject', objectType: 'Opportunity', isCollection: true },
    { name: 'Dates', dataType: 'Date', isCollection: true },
    { name: 'OtherDates', dataType: 'Date', isCollection: true },
    { name: 'Numbers', dataType: 'Number', isCollection: true },
  ],
};
const change = (control, value) =>
  control.dispatchEvent(new CustomEvent('change', { detail: { value } }));
function mount(value = '[]') {
  const element = createElement('c-js-named-collection-inputs', { is: Inputs });
  element.builderContext = context;
  element.value = value;
  document.body.appendChild(element);
  return element;
}
afterEach(() => {
  while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});

it('uses ordinary literal controls and preserves an entered zero', async () => {
  const element = mount();
  const changed = jest.fn();
  element.addEventListener('inputschange', changed);
  element.shadowRoot.querySelector('lightning-button').click();
  await flush();
  let row = element.shadowRoot.querySelector('section');
  let name = row.querySelector('lightning-input');
  name.value = 'Limit';
  change(name, 'Limit');
  change(row.querySelector('lightning-combobox[data-field="source"]'), 'value');
  await flush();
  row = element.shadowRoot.querySelector('section');
  change(row.querySelector('lightning-combobox[data-field="kind"]'), 'Number');
  await flush();
  const value = element.shadowRoot.querySelector('lightning-input[data-field="literal"]');
  value.value = '0';
  change(value, '0');
  await flush();
  expect(element.validate()).toEqual([]);
  expect(JSON.parse(JSON.parse(changed.mock.calls.at(-1)[0].detail.value)[0].valueJson)).toBe(0);
});

it('binds independent record types using plain names and resource pickers', async () => {
  const element = mount();
  const listener = jest.fn();
  element.addEventListener('inputschange', listener);
  for (const [name, resource] of [
    ['Customers', 'Accounts'],
    ['Orders', 'Opportunities'],
  ]) {
    element.shadowRoot.querySelector('lightning-button').click();
    await flush();
    const row = [...element.shadowRoot.querySelectorAll('section')].at(-1);
    const nameInput = row.querySelector('lightning-input');
    nameInput.value = name;
    change(nameInput, name);
    change(row.querySelector('lightning-combobox[data-field="resource"]'), resource);
    await flush();
  }
  const rows = JSON.parse(listener.mock.calls.at(-1)[0].detail.value);
  expect(rows).toEqual([
    { name: 'Customers', kind: 'Records', isCollection: true, records: '{!Accounts}' },
    { name: 'Orders', kind: 'Records', isCollection: true, records: '{!Opportunities}' },
  ]);
  expect(element.validate()).toEqual([]);
  expect(element.shadowRoot.textContent).not.toContain('input.Customers');
  expect(element.shadowRoot.querySelector('lightning-textarea')).toBeNull();
});
it('keeps native date references typed and generates size mappings for multiple collections', async () => {
  const element = mount(
    JSON.stringify([
      { name: 'Days', kind: 'Date', isCollection: true, resource: 'Dates' },
      { name: 'OtherDays', kind: 'Date', isCollection: true, resource: 'OtherDates' },
    ]),
  );
  const listener = jest.fn();
  element.addEventListener('inputschange', listener);
  element.shadowRoot.querySelector('lightning-button').click();
  await flush();
  const detail = listener.mock.calls.at(-1)[0].detail;
  expect(detail.nativeDates.map((row) => row.value)).toEqual([
    'Dates',
    '1900-01-01',
    'OtherDates',
    '1900-01-01',
  ]);
  expect(
    detail.inputSizes.transformValues[0].transformValueActions.map(
      (row) => row.inputParameters[0].value.elementReference,
    ),
  ).toEqual(['Dates', 'OtherDates']);
});
it('round-trips false, zero and merge-looking text as literal values', async () => {
  const rows = [
    { name: 'Enabled', kind: 'Boolean', isCollection: false, isLiteral: true, valueJson: 'false' },
    { name: 'Zero', kind: 'Number', isCollection: false, isLiteral: true, valueJson: '0' },
    {
      name: 'Message',
      kind: 'Text',
      isCollection: false,
      isLiteral: true,
      valueJson: '"\\u007b!Variable\\u007d"',
    },
  ];
  const element = mount(JSON.stringify(rows));
  const listener = jest.fn();
  element.addEventListener('inputschange', listener);
  element.shadowRoot.querySelector('lightning-button').click();
  await flush();
  const result = JSON.parse(listener.mock.calls.at(-1)[0].detail.value);
  expect(result.slice(0, 3).map((row) => JSON.parse(row.valueJson))).toEqual([
    false,
    0,
    '{!Variable}',
  ]);
  expect(result[2].valueJson).not.toContain('{!');
});
it('reports duplicate names and removes all native bindings with the last row', async () => {
  const element = mount(
    JSON.stringify([
      { name: 'Repeated', kind: 'Number', isCollection: true, resource: 'Numbers' },
      { name: 'Repeated', kind: 'Date', isCollection: true, resource: 'Dates' },
    ]),
  );
  expect(element.validate().some((error) => error.errorString.includes('different name'))).toBe(
    true,
  );
  const listener = jest.fn();
  element.addEventListener('inputschange', listener);
  for (let i = 0; i < 2; i++) {
    element.shadowRoot.querySelector('lightning-button-icon').click();
    await flush();
  }
  const detail = listener.mock.calls.at(-1)[0].detail;
  expect(JSON.parse(detail.value)).toEqual([]);
  expect(detail.nativeDates).toEqual([]);
  expect(detail.inputSizes).toBeNull();
  expect(element.validate()).toEqual([]);
});
