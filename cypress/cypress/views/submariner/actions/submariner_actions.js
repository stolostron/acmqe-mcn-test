/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2021 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { clusterSetMethods } from '../../../views/clusterset/clusterset'

export const submarinerClusterSetMethods = {

    // The function verifies that submariner deployment exists.
    submarinerClusterSetShouldExist: (clusterSetName) => {
        clusterSetMethods.clusterSetShouldExist(clusterSetName)
        cy.get('[data-label=Name]').eq(1).click(15, 30)
        cy.get('.pf-c-nav__link').contains('Submariner add-ons').click()
    },

    // The function adds the AWS an GCP clusters to the cluster set.
    // start position: from the 'Cluster set' list.
    manageClusterSet: (managed_clusters_list, clusterSetName) => {
        cy.get('.pf-c-text-input-group__text-input').type(clusterSetName)
        cy.get('[data-label="Name"]').contains(clusterSetName).click()
        cy.get('#clusters').contains('Go to Managed clusters').click()
        cy.wait(500)
        cy.get('.pf-c-empty-state__primary > .pf-c-button').click()
        cy.get('[data-label="Name"]').each(($el, index) => {
            if (index > 0) {
                if (!$el.text().includes('local-cluster')){// skip the local
                    if (managed_clusters_list.length > 0){
                        cy.get('[data-label=Name]').eq(index).then(($name) => { // get clusters from given list
                            if (managed_clusters_list.includes($name.text())){
                                cy.get('[type="checkbox"]').eq(index).click()
                            }
                        })
                    }
                    else{
                        cy.get('[data-label=Infrastructure]').eq(index).then(($platform) => { // get cluster patform
                            if ($platform.text().includes('Google') || $platform.text().includes('Amazon')){
                                cy.get('[type="checkbox"]').eq(index).click()
                            }
                        })
                    }
                }
            }
        })
        cy.get('#save').click()//review
    },

    // The function checks if the current data label exists and contains the correct message
    testTheDataLabel: (dataLabel, textToHave, messageToHave) => {
        cy.get(dataLabel).each(($el, index) => {
            if (index > 0){
                cy.wrap($el).click(40, 30, { timeout: 300000, interval: 3000 }).should('have.text', textToHave, { timeout: 300000, interval: 3000 })
                cy.get('.pf-c-popover__content').contains(messageToHave).should('exist').and('be.visible')
            }
        })
        cy.get(dataLabel).eq(-1).click(40, 30)
    }
}


