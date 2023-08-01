/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2023 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { clusterSetMethods } from '../views/clusterset/clusterset'

describe('submariner - validate submariner addon tab', {
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

    it('test the Submariner add-ons', { tags: ['addon'] }, function () {
        let clusterSetName = Cypress.env('CLUSTERSET')+'-'+(Math.random() + 1).toString(36).substring(4)
        cy.log('create a cluster set named ' + clusterSetName)
        clusterSetMethods.createClusterSet(clusterSetName)
        cy.get('.pf-c-text-input-group__text-input').type(clusterSetName)
        cy.contains(clusterSetName).should('exist').click({timeout: 3000})
        cy.get('.pf-c-nav__link').contains('Submariner add-ons').should('exist')
        cy.log("submariner add-ons tab was found")
        cy.log("delete the cluster set named " + clusterSetName)
        clusterSetMethods.deleteClusterSet(clusterSetName)
    })
})
