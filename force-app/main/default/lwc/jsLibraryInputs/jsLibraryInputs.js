import { LightningElement, api, wire } from 'lwc';
import listLibraries from '@salesforce/apex/JsLibraryController.listLibraries';

export default class JsLibraryInputs extends LightningElement {
  @wire(listLibraries) choices;
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
      this.rows = (
        typeof value === 'string' && value ? JSON.parse(value) : Array.isArray(value) ? value : []
      ).map((row) => ({ ...row, id: String(this.nextId++) }));
    } catch {
      this.rows = [];
    }
  }
  get options() {
    return this.choices?.data || [];
  }
  get loadError() {
    return !!this.choices?.error;
  }
  handleAdd() {
    this.rows = [...this.rows, { id: String(this.nextId++), name: '', resource: '' }];
    this.publish();
  }
  handleRemove(event) {
    this.rows = this.rows.filter((row) => row.id !== event.currentTarget.dataset.id);
    this.publish();
  }
  handleField(event) {
    const { id, field } = event.target.dataset;
    const value = event.detail?.value ?? event.target.value;
    this.rows = this.rows.map((row) => (row.id === id ? { ...row, [field]: value } : row));
    this.publish();
  }
  publish() {
    this.lastEmitted = JSON.stringify(this.rows.map(({ name, resource }) => ({ name, resource })));
    this.dispatchEvent(
      new CustomEvent('librarieschange', {
        detail: { value: this.lastEmitted, count: this.rows.length },
      }),
    );
  }
  @api validate() {
    const errors = [],
      names = new Set();
    for (const row of this.rows) {
      if (
        !/^[A-Za-z][A-Za-z0-9_]*$/.test(row.name) ||
        ['constructor', 'prototype'].includes(row.name)
      )
        errors.push({
          key: row.id + 'name',
          errorString:
            'Give the library a name starting with a letter, using letters, numbers, or underscores.',
        });
      if (names.has(row.name))
        errors.push({
          key: row.id + 'duplicate',
          errorString: 'Use a different name for each library.',
        });
      names.add(row.name);
      if (!row.resource)
        errors.push({
          key: row.id + 'resource',
          errorString: 'Choose a JavaScript Static Resource.',
        });
    }
    return errors;
  }
}
