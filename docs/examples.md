# Calculation examples

Configure the named inputs exactly as listed. These are JavaScript function bodies for the calculation area. Use a Decision on success and Read JavaScript Result for each output you need.

## Sum and threshold

Inputs: Amounts (Number collection), Threshold (Number).

```javascript
var total = input.Amounts.reduce(function (sum, amount) {
  return sum + amount;
}, 0);
return { Total: total, NeedsApproval: total > input.Threshold };
```

Read Total as Number and NeedsApproval as Boolean. Empty Amounts returns zero.

## Clean and deduplicate text

Input: Labels (Text collection).

```javascript
var seen = new Map();
var labels = [];
input.Labels.forEach(function (value) {
  var label = (value || '').trim();
  if (label && !seen.has(label)) {
    seen.set(label, true);
    labels.push(label);
  }
});
return { Labels: labels };
```

Read Labels as Text collection and use textValues. This treats case differences as distinct; uppercase/lowercase deliberately if you need different behavior.

## Join Accounts to Opportunities

Inputs: Customers (Account collection with Id and Name), Orders (Opportunity collection with AccountId, Name, and Amount).

```javascript
var customers = new Map();
input.Customers.forEach(function (customer) {
  customers.set(customer.Id, customer.Name);
});
var rows = input.Orders.map(function (order) {
  return {
    OrderName: order.Name,
    CustomerName: customers.get(order.AccountId) || '',
    Amount: order.Amount || 0,
  };
});
return { Rows: rows };
```

Rows is a custom structure, not an Opportunity record collection. Read it as JSON or use Prepare Portwood Data for a Rows loop. To return actual Opportunity records, return flat Opportunity field names and select Records/Opportunity in the reader.

## Group amounts by Account

Input: Orders (Opportunity collection with AccountId and Amount).

```javascript
var totals = new Map();
input.Orders.forEach(function (order) {
  var key = order.AccountId || 'Unassigned';
  totals.set(key, (totals.get(key) || 0) + (order.Amount || 0));
});
var groups = [];
var iterator = totals.entries();
var next = iterator.next();
while (!next.done) {
  var pair = next.value;
  groups.push({ AccountKey: pair[0], Total: pair[1] });
  next = iterator.next();
}
return { Groups: groups };
```

Groups is returned as JSON; Portwood can render it as a loop. Use a dedicated output collection with Salesforce field names if a later record action requires records.

## Return records for a later authorized update

Input: Orders (Opportunity collection with Id and Description).

```javascript
return {
  Orders: input.Orders.map(function (order) {
    return { Id: order.Id, Description: (order.Description || '').trim() };
  }),
};
```

Read Orders as Records with object API name Opportunity. After checking reader success, use its records output in a separate Update Records element if that is the intended, authorized operation. ApexJS itself performs no update.

## Add a UTC calendar day

Input: DueDates (Date collection).

```javascript
return {
  Dates: input.DueDates.map(function (value) {
    if (value === null) return null;
    var date = new Date(value);
    date.setUTCDate(date.getUTCDate() + 1);
    return date.toISOString().substring(0, 10);
  }),
};
```

Read Dates as Date collection. This example performs UTC calendar arithmetic, not business-day or user-timezone scheduling.

## Use a library and prepare Portwood output

Input: Amounts (Number collection). Add ApexJSExampleTools as library Tools.

```javascript
return {
  Title: 'Proposal summary',
  Summary: { Total: libraries.Tools.round(libraries.Tools.sum(input.Amounts), 2) },
  Amounts: input.Amounts,
};
```

With Prepare Portwood Data, use `{Title}`, `{Summary.Total}`, and an Amounts loop containing `{Value}`. Pass jsonData to Generate Document. The same resultJson can be read downstream without rerunning the calculation.
