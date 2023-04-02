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

Cypress.Commands.add('login', (OC_CLUSTER_USER, OC_CLUSTER_PASS, OC_IDP) => {
  const managedclustersPath = '/multicloud/infrastructure/clusters/managed'
  const user = OC_CLUSTER_USER || Cypress.env('OC_CLUSTER_USER')
  const password = OC_CLUSTER_PASS || Cypress.env('OC_CLUSTER_PASS')
  const idp = OC_IDP || Cypress.env('OC_IDP')

  cy.intercept(managedclustersPath).as('clustersPagePath')
  cy.visit(managedclustersPath, { 
    onBeforeLoad(win) {
      win.localStorage.setItem(
        cy.config().baseUrl + managedclustersPath + '/clusteronboardingmodal', 'hide'
      )
    },
  })
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
    cy.get('#page-main-header', { timeout: 30000 }).should('exist')
  })

  // Upon successful login, should be able to see the user menu in the navigation
  cy.get('nav[data-test="user-dropdown"] > button[aria-label="User menu"]').should('exist').then(() => {
    cy.log('Login successful! Ready to start testing...')
  })
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

Cypress.Commands.add('failOnErrorResponseStatus', (resp, errorMsg) => {
  expect(resp.status, errorMsg + " " + resp.body.message).to.match(/20[0,1]/)
})

Cypress.Commands.add('ocGetHubClusterVersion', () => {
  cy.exec('oc login --insecure-skip-tls-verify=true --username '+Cypress.env('OC_CLUSTER_USER')+' --password '+ Cypress.env('OC_CLUSTER_PASS')+ ' ' +constants.apiUrl)
  cy.exec('oc get clusterversion -ojsonpath="{.items[0].status.desired.version}"')
    .then(result => {
      cy.wrap(result.stdout.trim().slice(0,4)).as("hubOCPVersion")
    })
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
})