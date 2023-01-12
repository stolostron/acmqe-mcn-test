/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2023 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { submarinerClusterSetMethods } from '../views/submariner/actions/submariner_actions'
import { clusterSetMethods } from '../views/clusterset/clusterset'

describe('submariner - Deployment validation', {
    tags: ['@submariner'],
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
        let clusterSetName = Cypress.env('CLUSTERSET_NAME')
        let nattPort = Cypress.env('NATT_PORT')
        clusterSetMethods.createClusterSet(clusterSetName) 
        submarinerClusterSetMethods.manageClusterSet(clusterSetName)

        cy.get('button').contains('Save').click()
        cy.contains('Submariner add-ons', {timeout: 3000}).should('exist').click()
        cy.get('#install-submariner').click()
        cy.get('#install-submariner').click()
        cy.get('#available-clusters-input-toggle-select-multi-typeahead-typeahead').click()
        cy.get('.pf-c-select__menu-item').click({multiple: true})
        cy.get('#globalist-enable').click({ force: true })
        cy.get('button').contains('Next').click()
        cy.get('#natt-port').type('{selectAll}'+nattPort)
        for (let i=0; i<2; i++) {
            cy.get('button').contains('Next').click()
        }
        cy.get('button').contains('Install').click()

        cy.timeout(210000)
        submarinerClusterSetMethods.testTheDataLabel('[data-label="Connection status"]', 'Healthy', 'established')
        submarinerClusterSetMethods.testTheDataLabel('[data-label="Agent status"]', 'Healthy', 'is deployed on managed cluster')
        submarinerClusterSetMethods.testTheDataLabel('[data-label="Gateway nodes labeled"]', 'Nodes labeled', 'submariner.io/gateway')
    })
})

