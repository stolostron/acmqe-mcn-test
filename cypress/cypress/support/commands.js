/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2022 Red Hat, Inc.
 ****************************************************************************** */

// ***********************************************
// This example commands.js shows you how to
// create various custom commands and overwrite
// existing commands.
//
// For more comprehensive examples of custom
// commands please read more here:
// https://on.cypress.io/custom-commands
// ***********************************************

import 'cypress-wait-until'
import 'cypress-fill-command'
import 'cypress-localstorage-commands'
import * as constants from './constants'

import { acmHeaderSelectors } from '../views/header'
import { commonElementSelectors } from '../views/common/commonSelectors'

// Openshift Login
Cypress.Commands.add('managedClusterLogin', (apiUrl, user, password) => {
      cy.exec(`oc login --server=${apiUrl} -u ${user} -p ${password} --insecure-skip-tls-verify`, {timeout: 40 * 1000})
      //cy.wait(3*1000)
  })

Cypress.Commands.add('login', (OC_CLUSTER_USER, OC_CLUSTER_PASS, OC_IDP) => {
  const managedclustersPath = '/multicloud/infrastructure/clusters/managed'
  const user = OC_CLUSTER_USER || Cypress.env('OC_CLUSTER_USER')
  const password = OC_CLUSTER_PASS || Cypress.env('OC_CLUSTER_PASS')
  const idp = OC_IDP || Cypress.env('OC_IDP')

  cy.intercept(managedclustersPath).as('clustersPagePath')
  cy.visit(managedclustersPath, { failOnStatusCode: false })
  if (Cypress.config().baseUrl.startsWith("https://multicloud-console.apps")) {
    cy.url().then((url) => {
      if (!url.includes('oauth-openshift')) {
        cy.get('body').then((body) => {
          if (body.find('.pf-c-page__header').length === 0) {
            cy.log("Clicking 'Log in with OpenShift' button")
            cy.get('.panel-login').get('button').click()
          }
        })
      }
    })
  }
  cy.get('body').then(body => {
    // Check if logged in
    if (body.find(acmHeaderSelectors.mainHeader).length === 0) {
      if (body.text().includes('Log in with OpenShift')) {
        cy.contains('Log in with OpenShift').click()
      }
    }
  })

  cy.get('.pf-c-login__main').should('exist').then(body => {
    if (body.find('.idp').length != 0)
      cy.contains(idp).click()
    cy.get('#inputUsername').click().focused().type(user)
    cy.get('#inputPassword').click().focused().type(password)
    cy.get('button[type="submit"]').click()
    cy.get(acmHeaderSelectors.mainHeader, { timeout: 30000 }).should('exist')
  })

  // Verify we're on clusters page to start, after we log in. then hide the default modal by setting our cache.
  cy.wait('@clustersPagePath').then(() => {
    cy.setLocalStorage(cy.config().baseUrl + managedclustersPath + '/clusteronboardingmodal', 'hide')
  })
})

Cypress.Commands.add('waitUntilContains', (selector, text, options) => {
  cy.waitUntil(() => cy.ifContains(selector, text), options)
})

Cypress.Commands.add('checkCondition', (selector, condition, action) => {
  return cy.get('body').then($body => {
    var $elem = $body.find(selector)
    var result = condition($elem)
    if (result == true && action) {
      return action($elem)
    }

    return cy.wrap(result)
  })
})

Cypress.Commands.add('ifNotContains', (selector, text, action) => {
  return cy.checkCondition(selector, ($elem) => !$elem || !$elem.text().includes(text), action)
})

Cypress.Commands.add('ifContains', (selector, text, action) => {
  return cy.checkCondition(selector, ($elem) => $elem && $elem.text().includes(text), action)
})

Cypress.Commands.add('failOnErrorResponseStatus', (resp, errorMsg) => {
  expect(resp.status, errorMsg + " " + resp.body.message).to.match(/20[0,1]/)
})

Cypress.Commands.add('logout', () => {
  if (Cypress.config().baseUrl.startsWith("https://multicloud-console.apps")) {
    cy.get(acmHeaderSelectors.headerTools.userDropdown, { timeout: 20000 }).click()
    cy.contains(commonElementSelectors.elements.button, acmHeaderSelectors.headerTools.text.logout).click()
  } else {
    cy.get(acmHeaderSelectors.headerTools.OCPuserDropdown, { timeout: 20000 }).click()
    cy.contains(commonElementSelectors.elements.button, acmHeaderSelectors.headerTools.text.ocpLogout).click()
  }
})

Cypress.Commands.add('paste', {
  prevSubject: true,
  element: true
}, ($element, text) => {

  const subString = text.substr(0, text.length - 1)
  const lastChar = text.slice(-1)

  $element.text(subString)
  $element.val(subString)
  cy.get($element).type(lastChar).then(() => {
    if ($element.val() !== text) // first usage only setStates the last character for some reason
      cy.get($element).clear().type(text)
  })
})

Cypress.Commands.add("acquireToken", () => {
  cy
    .request({
      method: "HEAD",
      url:
        constants.authUrl +
        "/oauth/authorize?response_type=token&client_id=openshift-challenging-client",
      followRedirect: false,
      headers: {
        "X-CSRF-Token": 1
      },
      auth: {
        username: Cypress.env("OC_CLUSTER_USER"),
        password: Cypress.env("OC_CLUSTER_PASS")
      }
    })
    .then(resp => {
      return (resp.headers.location.match(/access_token=([^&]+)/)[1])
    });
}),

Cypress.Commands.add("setAPIToken", () => {
  cy.acquireToken().then(token => {
    Cypress.env("token", token)
  })
})

Cypress.Commands.add("clearOCMCookies", () => {
  cy.clearCookie("acm-access-token-cookie");
  cy.clearCookie("_oauth_proxy");
  cy.clearCookie("XSRF-TOKEN");
  cy.clearCookie("_csrf");
  cy.clearCookie("openshift-session-token");
  cy.clearCookie("csrf-token");
}),

Cypress.Commands.add('getClusterInfo', (hive_cluster_name) => {
      const cluster_info_dict = {}
      // Go the cluster from the Clusters table
      cy.get('tr').contains(hive_cluster_name).then(($tr) => {
          // Add hive_cluster_name to the environment variables
          Cypress.env(hive_cluster_name + "_name", hive_cluster_name)
          cy.log(hive_cluster_name)
          cluster_info_dict[hive_cluster_name + "_name"] = hive_cluster_name
          
          // Go into the cluster's page
          cy.wrap($tr).closest('tr').find('a').click()
      })
      // Get the Hive Cluster URL
      cy.get('.pf-c-description-list__text').contains('Console URL').then((url) => {
          cy.wrap(url).closest('div.pf-c-description-list__group').then((parent) => {
              cy.wrap(parent).find('.pf-c-button.pf-m-link.pf-m-inline').invoke('text').then((hive_cluster_url) => {
                  Cypress.env(hive_cluster_name + '_url', hive_cluster_url)
                  cy.log(hive_cluster_url)
                  cluster_info_dict[hive_cluster_name + '_url'] = hive_cluster_url
              })
          })
      })
      // Get the Hive Cluster Username
      cy.get('.credentials-toggle').contains('Reveal credentials').click()
      cy.get('#username-credentials').invoke('text').then((hive_cluster_user) => {
          Cypress.env(hive_cluster_name + '_user', hive_cluster_user)
          cy.log(hive_cluster_user)
          cluster_info_dict[hive_cluster_name + '_user'] = hive_cluster_user
          })
      // Get the Hive Cluster password
      cy.get('#password-credentials').invoke('text').then((hive_cluster_pwd) => {
          Cypress.env(hive_cluster_name + '_pwd', hive_cluster_pwd)
          cy.log(hive_cluster_pwd)
          cluster_info_dict[hive_cluster_name + '_pwd'] = hive_cluster_pwd
          })

      // Get the Hive Cluster API Address
      cy.get('#kube-api-server').invoke('text').then((hive_cluster_api) => {
          Cypress.env(hive_cluster_name + '_api', hive_cluster_api)
          cy.log(hive_cluster_api)
          cluster_info_dict[hive_cluster_name + '_api'] = hive_cluster_api
          })

          // Get the Hive Cluster Status
      cy.get('.pf-c-description-list__group').contains('Status').then((status) => {
          cy.wrap(status).closest('.pf-c-description-list__group').find('.pf-c-description-list__description').invoke('text').then((hive_cluster_status) => {
          Cypress.env(hive_cluster_name + '_status', hive_cluster_status)
          cy.log(hive_cluster_status)
          cluster_info_dict[hive_cluster_name + '_status'] = hive_cluster_status
          
          // Add the hive clusters credentials dictionary into the environment variables
          Cypress.env(hive_cluster_name + '_info', cluster_info_dict)
          })
      })

      // go back to the clusters table
      cy.get(':nth-child(1) > .pf-c-breadcrumb__link').click()
  })
