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
    CLUSTERSET: "submariner",
    SUBMARINER_IPSEC_NATT_PORT: "4505",
    DOWNSTREAM_CATALOG_SOURCE: "submariner-catalog",
    MANAGED_CLUSTERS: ""
  },

  e2e: {
    setupNodeEvents(on, config) {
      require('@cypress/grep/src/plugin')(config)
      return config;
    },
  },
});
