import { createElement } from 'lwc';
import Editor from 'c/jsPortwoodDataEditor';
jest.mock(
  '@salesforce/apex/JsLibraryController.listLibraries',
  () => ({
    default: require('@salesforce/wire-service-jest-util').createApexTestWireAdapter(jest.fn()),
  }),
  { virtual: true },
);
afterEach(() => {
  while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});
it('keeps no-code data valid but propagates the calculation requirement for selected libraries', async () => {
  const element = createElement('c-js-portwood-data-editor', { is: Editor });
  element.inputVariables = [{ name: 'namedInputs', value: '[]' }];
  document.body.appendChild(element);
  await Promise.resolve();
  expect(element.validate()).toEqual([]);
  element.inputVariables = [
    { name: 'namedInputs', value: '[]' },
    { name: 'libraries', value: '[{"name":"Tools","resource":"ApexJSExampleTools"}]' },
  ];
  await Promise.resolve();
  expect(element.validate().some((row) => row.key === 'source')).toBe(true);
});
