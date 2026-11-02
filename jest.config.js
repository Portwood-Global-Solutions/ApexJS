const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    coverageProvider: 'v8',
  coverageThreshold: {global: {lines: 90, statements: 90, branches: 70, functions: 75}},
    collectCoverageFrom: ['force-app/main/default/lwc/**/*.js','!**/__tests__/**'],
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};
