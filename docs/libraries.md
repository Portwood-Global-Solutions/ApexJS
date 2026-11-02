# Bring your own JavaScript libraries

ApexJS can load compatible source from Static Resources and run it with a calculation in the calling Flow transaction. It compiles the source inside Apex automatically. There is no offline bytecode step and no network fetch at runtime.

## Module contract

Use an uncompressed UTF-8 JavaScript file with CommonJS exports. UMD bundles that select their CommonJS branch can also work. Each configured module gets its own `exports` and `module` scope. Its exported value is made available under the name you choose in `libraries`.

```javascript
// MyTools.js
exports.discount = function (amount, percent) {
  return Math.round(amount * (100 - percent)) / 100;
};
```

Exporting a function directly with `module.exports = function(...) { ... };` is supported too. Local module state is fresh for each action request. Module names must be unique and follow the same naming rules as data names.

## Upload and use a module

1. Review the source and its license. Confirm that it fits the [supported JavaScript](javascript-support.md).
2. In Salesforce Setup, open **Static Resources → New**. Give it a name such as `MyTools`, upload the uncompressed `.js` file, and save. Use a JavaScript or plain-text content type. ZIP resources are not supported by this loader.
3. In Run JavaScript on Collections or Prepare Portwood Data, open **Static Resource libraries (optional)**.
4. Click **Add library**. Name it **Tools** and select the Static Resource. Namespaced resources appear with their qualified names.
5. Add ordinary named Flow data such as Amount and Percent.
6. In the separate calculation area, call the exported function and return a result:

```javascript
return { Discounted: libraries.Tools.discount(input.Amount, input.Percent) };
```

7. Check success and read Discounted as Number downstream. Prepare Portwood Data requires a calculation when libraries are selected.

`ApexJSExampleTools` is included as a small working example. Name it Tools and use:

```javascript
return {
  Summary: {
    Total: libraries.Tools.round(libraries.Tools.sum(input.Amounts), 2),
  },
};
```

You can add multiple named modules. Module source bodies are cached only within the current Apex transaction; mutable JavaScript module state is not shared between requests. The source hash covers the combined module source and calculation.

## What does not automatically work

- `import` and `export` syntax, TypeScript, JSX, or npm package resolution.
- `require(...)` dependencies. Bundle dependencies into a compatible self-contained CommonJS/UMD file before uploading.
- Browser APIs such as DOM, canvas, WebGL, or fetch; Node APIs such as filesystem and process are also unavailable.
- Libraries that need timers, sockets, remote events, workers, or an external asynchronous event loop.
- All ECMAScript features. Class syntax, arrow functions, and other syntax outside the documented subset must be transformed before upload.

Raw compatible source needs no preprocessing. A library distributed in an unsupported syntax/module format does require an appropriate build step. A Static Resource is a source location, not a guarantee of compatibility.

## Capacity and failure behavior

Library startup, the calculation, and result generation share the Flow transaction and interpreter budgets. The normal synchronous source limit is 262,144 characters for the **combined** generated program, including wrappers and the calculation. Token/node/step limits and Salesforce CPU/heap can be reached first. There is no promise that a library below the source limit will execute within the transaction.

ApexJS checks resource content type and size before loading source. The loader performs metadata/body queries for each uncached resource and reuses the body within the transaction. It checks remaining SOQL capacity before those queries. No library-specific native substitutions or downloaded vendor libraries are included.

A missing asset, unsupported syntax, thrown startup error, runaway startup, or oversized result returns a failed action with no partial result. Add success and fault branches as described in the admin guide.

The older large-library Queueable/cache experiment is not part of this release. General PDF, spreadsheet, graphics, and machine-learning libraries require their own compatibility and workload validation; the repository does not claim support for them.
