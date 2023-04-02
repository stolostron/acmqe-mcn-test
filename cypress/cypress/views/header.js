/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2022 Red Hat, Inc.
 ****************************************************************************** */
/// <reference types="cypress"/>

import { commonElementSelectors, commonPageMethods } from './common/commonSelectors'

export const acmHeaderSelectors = {
    mainHeader: ".pf-c-page__header",
    leftNavigation: {
        hamburbgerButton: "button[aria-label='Global navigation']",
        leftSideBar: '#page-sidebar',
        leftSideBarNav: 'nav[aria-label="Global"]',
        leftSideBarNavList: 'nav[aria-label="Global"] ui',
        listItemsText: {
            credentials: "Credentials",
            infrastructure: 'Infrastructure',
            infrastructureText: {
                clusters: "Clusters",
                automation: "Automation",
                hostInventory: "Host inventory"
            },
        }
    },
    headerTools: {
        userDropdown: 'nav button[aria-label="user-menu"]',
        OCPuserDropdown: 'nav button[aria-label="User menu"]',
        text: {
            logout: 'Logout',
            ocpLogout: 'Log out'
        }
    }
}

export const acm23xheaderMethods = {
    // left navigation methods
    openMenu: () => {
        cy.get(acmHeaderSelectors.leftNavigation.leftSideBar).should('exist').and('be.visible')
        // The cluster switcher dropdown placement is different from OCP 4.13+
        cy.ocGetHubClusterVersion()   
        .then( (result) => {
          cy.log(`ocp version is ${result}`)
          if (Number(result) > ('4.12')) {
              cy.get(`[data-test-id='cluster-dropdown-toggle']`)
                .click()
              cy.get(`[data-test-id='cluster-dropdown-item']`)
                .contains('All Clusters')
                .click()
          } else {
              cy.get('.oc-nav-header > .pf-c-dropdown > button')
                .first()
                .click()
              cy.contains('All Clusters')
                .click()
          }
        })
    },

    expandInfrastructure: () => {
        cy.contains(commonElementSelectors.elements.button, acmHeaderSelectors.leftNavigation.listItemsText.infrastructure).then($expand => {
            if ($expand.attr('aria-expanded') == 'false') {
                cy.contains(commonElementSelectors.elements.button, acmHeaderSelectors.leftNavigation.listItemsText.infrastructure).click({ timeout: 20000 })
                cy.contains(commonElementSelectors.elements.a, acmHeaderSelectors.leftNavigation.listItemsText.infrastructureText.clusters, { timeout: 5000 }).should('exist')
            }
        })
    },

    goToClusters: () => {
        acm23xheaderMethods.openMenu()
        cy.get(acmHeaderSelectors.leftNavigation.leftSideBar, { timeout: 20000 }).should('exist')

        acm23xheaderMethods.expandInfrastructure()
        cy.contains(commonElementSelectors.elements.a, acmHeaderSelectors.leftNavigation.listItemsText.infrastructureText.clusters, { timeout: 5000 }).should('exist').click({ force: true })
        cy.get(commonElementSelectors.elements.pageMenu, { timeout: 50000 }).then(($body) => {
            if ($body.text().includes("You don't have any clusters")) {
                commonPageMethods.resourceTable.buttonShouldClickable("Create cluster", 'a')
                commonPageMethods.resourceTable.buttonShouldClickable("Import cluster", 'a')
                cy.get('a').contains('Create cluster', { timeout: 20000 }).should('exist').and('not.have.class', commonElementSelectors.elements.disabledButton)
                cy.get('a').contains('Import cluster', { timeout: 20000 }).should('exist').and('not.have.class', commonElementSelectors.elements.disabledButton)
            } else {
                commonPageMethods.resourceTable.buttonShouldClickable('#createCluster')
                commonPageMethods.resourceTable.buttonShouldClickable('#importCluster')
                cy.get('#createCluster', { timeout: 20000 }).should('exist').and('not.have.class', commonElementSelectors.elements.disabledButton)
                cy.get('#importCluster', { timeout: 20000 }).should('exist').and('not.have.class', commonElementSelectors.elements.disabledButton)
            }
        })
    },

    goToClustersWithUser: () => {
        acm23xheaderMethods.openMenu()
        cy.get(acmHeaderSelectors.leftNavigation.leftSideBar, { timeout: 20000 }).should('exist')

        acm23xheaderMethods.expandInfrastructure()
        cy.contains(commonElementSelectors.elements.a, acmHeaderSelectors.leftNavigation.listItemsText.infrastructureText.clusters, { timeout: 5000 }).should('exist').click({ force: true })
        cy.get(commonElementSelectors.elements.pageMenu, { timeout: 50000 }).then(($body) => {
            if ($body.text().includes("You don't have any clusters")) {
                cy.get('a').contains('Create cluster', { timeout: 20000 }).should('exist').and('have.class', 'pf-c-button pf-m-primary pf-m-aria-disabled')
                cy.get('a').contains('Import cluster', { timeout: 20000 }).should('exist').and('have.class', 'pf-c-button pf-m-primary pf-m-aria-disabled')
            } else {
                cy.get('#createCluster', { timeout: 20000 }).should('exist').and('have.class', 'pf-c-button pf-m-primary pf-m-aria-disabled')
                cy.get('#importCluster', { timeout: 20000 }).should('exist').and('have.class', 'pf-c-button pf-m-secondary pf-m-aria-disabled')
            }
        })
    },
}
