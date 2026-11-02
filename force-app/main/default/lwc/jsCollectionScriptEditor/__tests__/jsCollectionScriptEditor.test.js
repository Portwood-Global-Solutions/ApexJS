import { createElement } from 'lwc';
import Editor from 'c/jsCollectionScriptEditor';
jest.mock(
  '@salesforce/apex/JsLibraryController.listLibraries',
  () => ({
    default: require('@salesforce/wire-service-jest-util').createApexTestWireAdapter(jest.fn()),
  }),
  { virtual: true },
);
const flush = () => Promise.resolve();
function mount(inputVariables = []) {
  const element = createElement('c-js-collection-script-editor', { is: Editor });
  element.inputVariables = inputVariables;
  document.body.appendChild(element);
  return element;
}
afterEach(() => {
  while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});

it('clears native transport when reusing an earlier result for Portwood', async () => {
  const element = createElement('c-js-collection-script-editor', { is: Editor });
  element.portwoodMode = true;
  element.inputVariables = [{ name: 'namedInputs', value: '[]' }];
  const deleted = jest.fn(),
    changed = jest.fn();
  element.addEventListener('configuration_editor_input_value_deleted', deleted);
  element.addEventListener('configuration_editor_input_value_changed', changed);
  document.body.appendChild(element);
  await flush();
  const mode = [...element.shadowRoot.querySelectorAll('lightning-combobox')].find(
    (row) => row.label === 'Data source',
  );
  mode.dispatchEvent(new CustomEvent('change', { detail: { value: 'json' } }));
  await flush();
  expect(deleted.mock.calls.map(([event]) => event.detail.name)).toEqual(
    expect.arrayContaining([
      'namedInputs',
      'inputSizes',
      'nativeNumbers',
      'nativeDates',
      'source',
      'libraries',
    ]),
  );
  expect(element.validate()[0].key).toBe('existingJson');
  element.inputVariables = [
    { name: 'dataMode', value: 'JSON' },
    { name: 'existingJson', value: 'Calculate.resultJson' },
  ];
  await flush();
  expect(element.validate()).toEqual([]);
  mode.dispatchEvent(new CustomEvent('change', { detail: { value: 'direct' } }));
  await flush();
  expect(changed.mock.calls.map(([event]) => event.detail)).toContainEqual({
    name: 'namedInputs',
    newValue: '[]',
    newValueDataType: 'Apex',
  });
});

it('generates an example using the configured name and keeps calculations optional for plain Portwood data', async () => {
  const element = mount([
    {
      name: 'namedInputs',
      value: '[{"name":"MyOrders","kind":"Records","isCollection":true,"records":"{!Orders}"}]',
    },
  ]);
  await flush();
  const changed = jest.fn();
  element.addEventListener('configuration_editor_input_value_changed', changed);
  [...element.shadowRoot.querySelectorAll('lightning-button')]
    .find((row) => row.label === 'Insert example')
    .click();
  expect(changed.mock.calls.at(-1)[0].detail.newValue).toContain('input["MyOrders"].length');
  const blank = createElement('c-js-collection-script-editor', { is: Editor });
  blank.portwoodMode = true;
  blank.inputVariables = [{ name: 'namedInputs', value: '[]' }];
  document.body.appendChild(blank);
  await flush();
  expect(blank.validate()).toEqual([]);
  blank.inputVariables = [{ name: 'libraries', value: '[{"name":"Tools","resource":"MyTools"}]' }];
  await flush();
  expect(blank.validate().some((row) => row.key === 'source')).toBe(true);
});
it('persists an empty named input list for a source-only calculation', async () => {
  const element = createElement('c-js-collection-script-editor', { is: Editor });
  const changed = jest.fn();
  element.addEventListener('configuration_editor_input_value_changed', changed);
  document.body.appendChild(element);
  await flush();
  expect(changed.mock.calls.map(([event]) => event.detail)).toEqual(
    expect.arrayContaining([
      { name: 'dataMode', newValue: 'Direct', newValueDataType: 'String' },
      { name: 'namedInputs', newValue: '[]', newValueDataType: 'Apex' },
    ]),
  );
  expect(element.validate().some((row) => row.key === 'source')).toBe(true);
});
it('emits the Flow transform envelope and typed collectionElements rather than dropping mappings', async () => {
  const element = mount([{ name: 'source', value: 'return input;', valueDataType: 'String' }]);
  await flush();
  const changed = jest.fn();
  element.addEventListener('configuration_editor_input_value_changed', changed);
  const mapping = {
    isCollection: false,
    dataType: 'Apex',
    apexClass: 'JsFlowInputSizes',
    transformValues: [
      {
        transformValueActions: [
          {
            transformType: 'Count',
            outputFieldApiName: 'sizes[0]',
            inputParameters: [{ name: 'aggregationValues', value: { elementReference: 'Dates' } }],
          },
        ],
      },
    ],
  };
  const dates = [
    { value: 'Dates', valueDataType: 'reference' },
    { value: '1900-01-01', valueDataType: 'Date' },
  ];
  element.shadowRoot.querySelector('c-js-named-collection-inputs').dispatchEvent(
    new CustomEvent('inputschange', {
      detail: { value: '[]', inputSizes: mapping, nativeDates: dates },
    }),
  );
  const values = changed.mock.calls.map(([event]) => event.detail);
  expect(values).toEqual(
    expect.arrayContaining([
      { name: 'inputSizes', newValue: { transform: mapping }, newValueDataType: 'transform' },
      { name: 'nativeDates', newValue: dates, newValueDataType: 'collectionElements' },
    ]),
  );
});
it('saves calculation resources as references and library rows as structured Apex values', async () => {
  const element = mount();
  await flush();
  const changed = jest.fn();
  element.addEventListener('configuration_editor_input_value_changed', changed);
  const checkbox = element.shadowRoot
    .querySelector('lightning-accordion-section')
    .querySelector('lightning-input');
  checkbox.checked = true;
  checkbox.dispatchEvent(new CustomEvent('change'));
  await flush();
  element.shadowRoot
    .querySelector('lightning-accordion-section')
    .querySelector('lightning-combobox')
    .dispatchEvent(new CustomEvent('change', { detail: { value: 'AdminScript' } }));
  element.shadowRoot.querySelector('c-js-library-inputs').dispatchEvent(
    new CustomEvent('librarieschange', {
      detail: { value: '[{"name":"Tools","resource":"MyTools"}]' },
    }),
  );
  expect(changed.mock.calls.map(([event]) => event.detail)).toEqual(
    expect.arrayContaining([
      { name: 'source', newValue: 'AdminScript', newValueDataType: 'reference' },
      {
        name: 'libraries',
        newValue: '[{"name":"Tools","resource":"MyTools"}]',
        newValueDataType: 'Apex',
      },
    ]),
  );
});
