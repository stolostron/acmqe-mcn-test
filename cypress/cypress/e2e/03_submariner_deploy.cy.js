/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2023 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { submarinerClusterSetMethods } from '../views/submariner/actions/submariner_actions'
import { clusterSetMethods } from '../views/clusterset/clusterset'
import { clustersPages } from '../views/clusters/managedCluster'

describe('submariner - Deployment validation', {
    tags: ['@submariner', '@e2e'],
    retries: {
        runMode: 0,
        openMode: 0,
    }
}, function () {
    before(function () {
        cy.setAPIToken()
        cy.clearOCMCookies()
        cy.login()
    })

    it('test the Submariner add-ons install', { tags: ['deployment'] }, function () {
        let clusterSetName = Cypress.env('CLUSTERSET')
        let nattPort = Cypress.env('SUBMARINER_IPSEC_NATT_PORT')
        let source = Cypress.env('DOWNSTREAM_CATALOG_SOURCE')
        let managed_clusters_list = Cypress.env('MANAGED_CLUSTERS')
        let downstream = Cypress.env('DOWNSTREAM')

        //check if a cluster set named submariner already exists
        clustersPages.goToClusterSet()
        cy.get('.pf-c-text-input-group__text-input').type(clusterSetName)
        cy.get('[data-label=Name]').then(($clusterset) => {
            if ($clusterset.text().includes(clusterSetName)) {
                cy.log("found")
                cy.get('[data-label=Name]').contains(clusterSetName).click()
            }
            else{
                cy.log('not found')
                clusterSetMethods.createClusterSet(clusterSetName)
                submarinerClusterSetMethods.manageClusterSet(managed_clusters_list, clusterSetName)
                cy.get('button').contains('Save').click()
            }
        })

        cy.contains('Submariner add-ons', {timeout: 3000}).should('exist').click()
        cy.wait(500)
        cy.get('#install-submariner').click()
        cy.get('#available-clusters-input-toggle-select-multi-typeahead-typeahead').click()
        cy.get('.pf-c-select__menu-item').click({multiple: true})
        cy.get('#globalist-enable').click({ force: true })
        cy.get('button').contains('Next').click()

        cy.get('.pf-c-wizard__nav-list').eq(1).children().each(() => {
            cy.get('#natt-port').type('{selectAll}'+nattPort)
            if (downstream){
                cy.get('#isCustomSubscription').click()
                cy.get('#source').type('{selectAll}'+source)
            }
            cy.get('button').contains('Next').click()
        })

        cy.get('button').contains('Install').click()

        cy.wait(330000)
        submarinerClusterSetMethods.testTheDataLabel('[data-label="Gateway nodes labeled"]', 'Nodes labeled', 'submariner.io/gateway')
        submarinerClusterSetMethods.testTheDataLabel('[data-label="Agent status"]', 'Healthy', 'is deployed on managed cluster')
        submarinerClusterSetMethods.testTheDataLabel('[data-label="Connection status"]', 'Healthy', 'established')
    })
})

