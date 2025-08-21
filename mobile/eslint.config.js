/* Basic ESLint + TS config (optional). Adapt as needed */
export default [
  {
    files: ["**/*.ts", "**/*.tsx", "**/*.js"],
    languageOptions: {
      parserOptions: { project: "./tsconfig.json", tsconfigRootDir: process.cwd() }
    },
    plugins: { },
    rules: { }
  }
];