/* ApexJS example module. No external dependencies. */
exports.sum = function(values) {
  return values.reduce(function(total, value) { return total + value; }, 0);
};
exports.round = function(value, places) {
  var factor = Math.pow(10, places);
  return Math.round(value * factor) / factor;
};
