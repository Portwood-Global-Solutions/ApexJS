import { createElement } from 'lwc';
import Libraries from 'c/jsLibraryInputs';
import listLibraries from '@salesforce/apex/JsLibraryController.listLibraries';
jest.mock(
  '@salesforce/apex/JsLibraryController.listLibraries',
  () => ({
    default: require('@salesforce/wire-service-jest-util').createApexTestWireAdapter(jest.fn()),
  }),
  { virtual: true },
);
const flush = () => Promise.resolve();
afterEach(() => {
  while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});
it('lists Static Resources and persists plain library configuration', async () => {
  const element = createElement('c-js-library-inputs', { is: Libraries });
  element.value = '[]';
  const changed = jest.fn();
  element.addEventListener('librarieschange', changed);
  document.body.appendChild(element);
  listLibraries.emit([{ label: 'MyTools', value: 'MyTools' }]);
  await flush();
  element.shadowRoot.querySelector('lightning-button').click();
  await flush();
  const name = element.shadowRoot.querySelector('lightning-input');
  name.value = 'Tools';
  name.dispatchEvent(new CustomEvent('change', { detail: { value: 'Tools' } }));
  const choice = element.shadowRoot.querySelector('lightning-combobox');
  expect(choice.options).toEqual([{ label: 'MyTools', value: 'MyTools' }]);
  choice.dispatchEvent(new CustomEvent('change', { detail: { value: 'MyTools' } }));
  await flush();
  expect(element.validate()).toEqual([]);
  expect(JSON.parse(changed.mock.calls.at(-1)[0].detail.value)).toEqual([
    { name: 'Tools', resource: 'MyTools' },
  ]);
});
it('validates duplicate names and reports design-time access errors', async () => {
  const element = createElement('c-js-library-inputs', { is: Libraries });
  element.value = '[{"name":"Tools","resource":"A"},{"name":"Tools","resource":"B"}]';
  document.body.appendChild(element);
  expect(element.validate().some((row) => row.errorString.includes('different name'))).toBe(true);
  listLibraries.error({ message: 'Access denied' });
  await flush();
  expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('ApexJS Author');
  const changed = jest.fn();
  element.addEventListener('librarieschange', changed);
  element.shadowRoot.querySelector('lightning-button').click();
  await flush();
  expect(JSON.parse(changed.mock.calls.at(-1)[0].detail.value)).toHaveLength(1);
});
