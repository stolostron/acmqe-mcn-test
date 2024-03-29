/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2021 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { clusterSetMethods } from '../../../views/clusterset/clusterset'
import { clustersPages } from '../../../views/clusters/managedCluster'

export const submarinerClusterSetMethods = {

    // The function verifies that submariner cluster exists.
    submarinerClusterSetShouldExist: (clusterSetName) => {
        cy.log("verify that a cluster set named " + clusterSetName + " exists")
        clustersPages.goToClusterSet()
        cy.get('.pf-c-text-input-group__text-input').type(clusterSetName)

        return cy.get('[data-label=Name]')
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
                                cy.log('add ' + $name.text() + ' cluster to the cluster set ' + clusterSetName)
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
        cy.log("test the " + dataLabel + " label")
        let dataLabelForTest = '[data-label="'+dataLabel+'"]'
        cy.get(dataLabelForTest).each(($el, index) => {
            if (index > 0){
                cy.wrap($el).click(40, 30).then(() => {
                    cy.log("The data label '" + dataLabel + "' has the status: " + $el.text())
                    cy.wrap($el).should('have.text', textToHave)
                })

                cy.get('.pf-c-popover__content').then(($message) => {
                    cy.log("The data label '" + dataLabel + "' message is: " + $message.text())
                    cy.wrap($message.text()).should('include',messageToHave)  
                })
            }
        })
        cy.get(dataLabelForTest).eq(-1).click(40, 30)
    }
}


