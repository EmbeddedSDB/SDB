module.exports = {
  env: {
    es6: true,
    node: true, // Node.js 환경 활성화
  },
  parserOptions: {
    ecmaVersion: 2020, // 최신 ECMAScript 지원
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
    "no-undef": "off", // require, exports 등 허용
    "max-len": ["error", { code: 120 }], // 한 줄 길이 120자로 확장
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {}, // 전역 변수 명시 가능
};
