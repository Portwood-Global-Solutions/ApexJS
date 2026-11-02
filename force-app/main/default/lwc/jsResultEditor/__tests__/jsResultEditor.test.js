import { createElement } from 'lwc';
import Reader from 'c/jsResultEditor';
const flush = () => Promise.resolve();
afterEach(() => {
  while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});
it('selects earlier results and persists the default typed output', async () => {
  const element = createElement('c-js-result-editor', { is: Reader });
  element.builderContext = {
    actionCalls: [
      { name: 'Calculate', actionName: 'JsCollectionScriptAction', label: 'Calculate' },
    ],
  };
  element.inputVariables = [{ name: 'resultJson', value: 'Calculate.resultJson' }];
  const changed = jest.fn();
  element.addEventListener('configuration_editor_input_value_changed', changed);
  document.body.appendChild(element);
  await flush();
  expect(element.validate()).toEqual([]);
  expect(changed.mock.calls.map(([event]) => event.detail)).toContainEqual({
    name: 'outputType',
    newValue: 'Number',
    newValueDataType: 'String',
  });
});
it('maps record output to the chosen object type and reports missing configuration', async () => {
  const element = createElement('c-js-result-editor', { is: Reader });
  element.inputVariables = [{ name: 'outputType', value: 'Records' }];
  const mapped = jest.fn();
  element.addEventListener('configuration_editor_generic_type_mapping_changed', mapped);
  document.body.appendChild(element);
  await flush();
  expect(element.validate().map((row) => row.key)).toEqual(
    expect.arrayContaining(['resultJson', 'objectApiName']),
  );
  const object = [...element.shadowRoot.querySelectorAll('lightning-input')].find(
    (row) => row.placeholder === 'Opportunity',
  );
  object.value = 'Opportunity';
  object.dispatchEvent(new CustomEvent('change'));
  expect(mapped.mock.calls.at(-1)[0].detail).toEqual({
    typeName: 'U__records',
    typeValue: 'Opportunity',
  });
});
