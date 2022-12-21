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
        cy.get('body').then(body => {
            if (body.find('#guided-tour-modal').length > 0) {
                cy.get('#guided-tour-modal').within(() => {
                    cy.get('button[aria-label="Close"]').click()
                })
            }
        })
        cy.get(acmHeaderSelectors.leftNavigation.leftSideBar, { timeout: 10 * 1000 }).should('exist').and('be.visible')
        var menuOpened = cy.get(acmHeaderSelectors.leftNavigation.leftSideBar).invoke('attr', 'aria-hidden')
        if (menuOpened == false) {
            cy.get(acmHeaderSelectors.leftNavigation.hamburbgerButton).click()
            cy.wait(500).get(acmHeaderSelectors.leftNavigation.leftSideBarNavList).should('be.visible').and('have.length', 6)
        }
        // Check if using OCP console here
        if (Cypress.config().baseUrl.startsWith("https://console-openshift-console.apps")) {
            // eslint-disable-next-line cypress/no-unnecessary-waiting
            cy.wait(1500)
            cy.get('.oc-nav-header > .pf-c-dropdown > button > .pf-c-dropdown__toggle-text')
                .first()
                .invoke('text')
                .then(txt => {
                    if (txt != 'All Clusters') {
                        cy.get('.oc-nav-header > .pf-c-dropdown > button')
                            .first()
                            .click({ timeout: 20000 })
                            .then(
                                () => {
                                    cy.get('.pf-c-dropdown__menu', { timeout: 2 * 1000 }).should('exist').contains("All Clusters").click()
                                })
                    }
                })
        }
    },

    expandInfrastructure: () => {
        // eslint-disable-next-line cypress/no-unnecessary-waiting
        cy.wait(1500).contains(commonElementSelectors.elements.button, acmHeaderSelectors.leftNavigation.listItemsText.infrastructure).then($expand => {
            if ($expand.attr('aria-expanded') == 'false') {
                // eslint-disable-next-line cypress/no-unnecessary-waiting
                cy.wait(1500).contains(commonElementSelectors.elements.button, acmHeaderSelectors.leftNavigation.listItemsText.infrastructure).click({ timeout: 20000, force: true })
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
