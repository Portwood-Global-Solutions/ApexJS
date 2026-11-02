import { LightningElement, api } from 'lwc';
export default class JsPortwoodDataEditor extends LightningElement {
  @api inputVariables = [];
  @api builderContext;
  @api genericTypeMappings = [];
  @api elementInfo;
  @api validate() {
    return this.template.querySelector('c-js-collection-script-editor')?.validate() || [];
  }
}
