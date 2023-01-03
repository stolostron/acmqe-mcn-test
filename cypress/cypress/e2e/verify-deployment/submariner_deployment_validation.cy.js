/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2022 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { submarinerClusterSetMethods } from '../../views/submariner/actions/submariner_actions'

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
    
    it('verify that a cluster set with deployment of submariner is exists.', { tags: ['verify'] }, function () {
        let clusterSetName = Cypress.env('CLUSTERSET_NAME')
        submarinerClusterSetMethods.submarinerClusterSetShouldExist(clusterSetName)
    })
    
    let testTheDataLabel = (dataLabel, textToHave, messageToHave) => {
        cy.get(dataLabel).each(($el, index) => {
            if (index > 0){
                cy.wrap($el).click(40, 30).should('have.text', textToHave)
                cy.get('.pf-c-popover__content').contains(messageToHave).should('exist').and('be.visible')
            }
        })
        cy.get(dataLabel).eq(-1).click(40, 30)
    }

    it('test the Connection status label', { tags: ['Connection'] }, function () {
        testTheDataLabel('[data-label="Connection status"]', 'Healthy', 'established')
    })

    it('test the Agent status label', { tags: ['Agent'] }, function () {
        testTheDataLabel('[data-label="Agent status"]', 'Healthy', 'is deployed on managed cluster')
    })

    it('test the Gateway nodes labeled label', { tags: ['Gateway'] }, function () {
        testTheDataLabel('[data-label="Gateway nodes labeled"]', 'Nodes labeled', 'submariner.io/gateway')
    }) 
})


