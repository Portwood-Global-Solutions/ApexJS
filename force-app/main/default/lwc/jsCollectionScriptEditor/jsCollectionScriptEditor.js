import { LightningElement, api } from 'lwc';
import { inputValue, emitInput, resultResources } from 'c/jsFlowEditorUtils';

export default class JsCollectionScriptEditor extends LightningElement {
  @api inputVariables = [];
  @api builderContext;
  @api genericTypeMappings = [];
  @api elementInfo;
  @api portwoodMode = false;
  modeOverride;
  sourceReferenceOverride;
  connectedCallback() {
    Promise.resolve().then(() => this.ensureDefaults());
  }
  get source() {
    return inputValue(this.inputVariables, 'source');
  }
  get namedInputs() {
    return inputValue(this.inputVariables, 'namedInputs') || '[]';
  }
  get libraries() {
    return inputValue(this.inputVariables, 'libraries') || '[]';
  }
  get hasLibraries() {
    try {
      return JSON.parse(this.libraries).length > 0;
    } catch {
      return false;
    }
  }
  get existingJson() {
    return inputValue(this.inputVariables, 'existingJson');
  }
  get collectionName() {
    return inputValue(this.inputVariables, 'collectionName') || 'Items';
  }
  get inputMode() {
    return (
      this.modeOverride ||
      (inputValue(this.inputVariables, 'dataMode') === 'JSON' ? 'json' : 'direct')
    );
  }
  get usesExistingJson() {
    return this.portwoodMode && this.inputMode === 'json';
  }
  get inputModes() {
    return [
      { label: 'Choose Flow data here', value: 'direct' },
      { label: 'Use an earlier calculation result', value: 'json' },
    ];
  }
  get sourceIsReference() {
    return (
      this.sourceReferenceOverride ??
      this.inputVariables.find((row) => row.name === 'source')?.valueDataType === 'reference'
    );
  }
  get sourceOptions() {
    return resultResources(this.builderContext).filter(
      (row) => row.value !== this.elementInfo?.apiName + '.resultJson',
    );
  }
  get calculationSections() {
    return this.source || this.hasLibraries ? ['calculation'] : [];
  }
  get sourceHelp() {
    return 'Use input and the names configured above. Return an object with the values and collections you need. Selected CommonJS modules are available in libraries by name.';
  }
  ensureDefaults() {
    if (!inputValue(this.inputVariables, 'dataMode')) emitInput(this, 'dataMode', 'Direct');
    if (!this.usesExistingJson && !inputValue(this.inputVariables, 'namedInputs'))
      emitInput(this, 'namedInputs', '[]', 'Apex');
  }
  handleDirectInputs(event) {
    this.ensureDefaults();
    emitInput(this, 'namedInputs', event.detail.value, 'Apex');
    for (const name of [
      'nativeDates',
      'nativeDateTimes',
      'nativeTexts',
      'nativeNumbers',
      'nativeBooleans',
    ])
      emitInput(
        this,
        name,
        event.detail[name]?.length ? event.detail[name] : '',
        'collectionElements',
      );
    emitInput(
      this,
      'inputSizes',
      event.detail.inputSizes ? { transform: event.detail.inputSizes } : '',
      'transform',
    );
  }
  handleLibraries(event) {
    this.ensureDefaults();
    emitInput(this, 'libraries', event.detail.value, 'Apex');
  }
  handleSourceMode(event) {
    this.sourceReferenceOverride = event.target.checked;
    emitInput(this, 'source', '');
  }
  handleSource(event) {
    this.ensureDefaults();
    emitInput(
      this,
      'source',
      event.detail?.value ?? event.target.value,
      this.sourceIsReference ? 'reference' : 'String',
    );
  }
  handleInputMode(event) {
    this.modeOverride = event.detail.value;
    emitInput(this, 'dataMode', this.inputMode === 'json' ? 'JSON' : 'Direct');
    if (this.inputMode === 'json')
      for (const name of [
        'namedInputs',
        'inputSizes',
        'nativeDates',
        'nativeDateTimes',
        'nativeTexts',
        'nativeNumbers',
        'nativeBooleans',
        'source',
        'libraries',
      ])
        emitInput(this, name, '');
    else {
      emitInput(this, 'existingJson', '');
      emitInput(this, 'namedInputs', '[]', 'Apex');
    }
  }
  handleExistingJson(event) {
    emitInput(this, 'existingJson', event.detail.value, 'reference');
  }
  handleCollectionName(event) {
    emitInput(this, 'collectionName', event.target.value);
  }
  handleExample() {
    let rows = [];
    try {
      rows = JSON.parse(this.namedInputs);
    } catch {
      rows = [];
    }
    const row = rows.find((item) => item.isCollection !== false) || rows[0];
    const source = row
      ? row.isCollection !== false
        ? 'return { summary: { count: input[' + JSON.stringify(row.name) + '].length } };'
        : 'return { value: input[' + JSON.stringify(row.name) + '] };'
      : 'return { message: "Hello from ApexJS" };';
    this.sourceReferenceOverride = false;
    emitInput(this, 'source', source);
  }
  @api validate() {
    this.ensureDefaults();
    if (this.usesExistingJson)
      return this.existingJson
        ? []
        : [{ key: 'existingJson', errorString: 'Choose the earlier JSON result.' }];
    const errors = [
      ...(this.template.querySelector('c-js-named-collection-inputs')?.validate() || []),
      ...(this.template.querySelector('c-js-library-inputs')?.validate() || []),
    ];
    if ((!this.portwoodMode || this.hasLibraries) && !this.source.trim())
      errors.push({
        key: 'source',
        errorString: 'Enter a calculation or choose a Flow text resource.',
      });
    return errors;
  }
}
