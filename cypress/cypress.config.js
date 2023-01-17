const { defineConfig } = require("cypress");

module.exports = defineConfig({
  chromeWebSecurity: false,
  reporter: "junit",

  reporterOptions: {
    mochaFile: "results/test-results-[hash].xml",
    toConsole: true,
  },

  screenshotsFolder: "results/screenshots",
  videosFolder: "results/videos",
  videoUploadOnPasses: false,
  viewportHeight: 1050,
  viewportWidth: 1680,

  env: {
    OC_IDP: "kube:admin",
    CLUSTERSET_NAME: "submariner",
    NATT_PORT: "4505"
  },

  e2e: {
    setupNodeEvents(on, config) {
      require('@cypress/grep/src/plugin')(config)
      return config;
    },
  },
});
