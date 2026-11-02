import { LightningElement, api } from 'lwc';
import { inputValue, emitInput, emitType, resultResources } from 'c/jsFlowEditorUtils';

export default class JsResultEditor extends LightningElement {
  @api inputVariables = [];
  @api builderContext;
  @api genericTypeMappings = [];
  @api elementInfo;
  manualReference = false;
  connectedCallback() {
    Promise.resolve().then(() => this.ensureType());
  }
  get jsonResource() {
    return inputValue(this.inputVariables, 'resultJson');
  }
  get path() {
    return inputValue(this.inputVariables, 'path');
  }
  get outputType() {
    return inputValue(this.inputVariables, 'outputType') || 'Number';
  }
  get objectApiName() {
    return inputValue(this.inputVariables, 'objectApiName');
  }
  get isRecords() {
    return this.outputType === 'Records';
  }
  get sourceOptions() {
    return resultResources(this.builderContext);
  }
  get hasSourceOptions() {
    return this.sourceOptions.length > 0;
  }
  get useManualReference() {
    return (
      this.manualReference ||
      !this.hasSourceOptions ||
      (this.jsonResource &&
        !this.sourceOptions.some((option) => option.value === this.jsonResource))
    );
  }
  get typeOptions() {
    return [
      'Text',
      'Number',
      'Boolean',
      'Date',
      'DateTime',
      'TextCollection',
      'NumberCollection',
      'BooleanCollection',
      'DateCollection',
      'DateTimeCollection',
      'Records',
      'JSON',
    ].map((value) => ({ label: value.replace('Collection', ' collection'), value }));
  }
  get outputName() {
    return {
      Text: 'textValue',
      Number: 'numberValue',
      Boolean: 'booleanValue',
      Date: 'dateValue',
      DateTime: 'dateTimeValue',
      TextCollection: 'textValues',
      NumberCollection: 'numberValues',
      BooleanCollection: 'booleanValues',
      DateCollection: 'dateValues',
      DateTimeCollection: 'dateTimeValues',
      Records: 'records',
      JSON: 'jsonValue',
    }[this.outputType];
  }
  ensureType() {
    const mapped = this.genericTypeMappings.find((item) => item.typeName === 'U__records');
    const target = this.objectApiName || mapped?.typeValue || 'Account';
    if (!mapped || mapped.typeValue !== target) emitType(this, 'U__records', target);
  }
  handleResource(event) {
    this.ensureType();
    emitInput(this, 'resultJson', event.detail.value ?? event.target.value, 'reference');
  }
  handleManualReference(event) {
    this.manualReference = event.target.checked;
    if (
      !this.manualReference &&
      this.jsonResource &&
      !this.sourceOptions.some((option) => option.value === this.jsonResource)
    )
      emitInput(this, 'resultJson', '', 'reference');
  }
  handlePath(event) {
    this.ensureType();
    emitInput(this, 'path', event.target.value);
  }
  handleOutputType(event) {
    this.ensureType();
    emitInput(this, 'outputType', event.detail.value);
  }
  handleObject(event) {
    const name = event.target.value.trim();
    emitInput(this, 'objectApiName', name);
    if (name) emitType(this, 'U__records', name);
  }
  @api validate() {
    this.ensureType();
    // The visible default must also exist as a literal action parameter.
    if (!inputValue(this.inputVariables, 'outputType'))
      emitInput(this, 'outputType', this.outputType);
    const errors = [];
    if (!this.jsonResource)
      errors.push({ key: 'resultJson', errorString: 'Choose the JSON result resource.' });
    if (this.isRecords && !this.objectApiName)
      errors.push({ key: 'objectApiName', errorString: 'Enter the output object API name.' });
    return errors;
  }
}
