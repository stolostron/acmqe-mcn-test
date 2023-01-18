/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2023 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { clusterSetMethods } from '../views/clusterset/clusterset'

describe('submariner - validate submariner addon tab', {
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

    it('test the Submariner add-ons', { tags: ['addon'] }, function () {
        let clusterSetName = Cypress.env('CLUSTERSET')+'-'+(Math.random() + 1).toString(36).substring(4)
        clusterSetMethods.createClusterSet(clusterSetName)
        cy.get('[data-label="Name"]').contains(clusterSetName).click()
        cy.get('.pf-c-nav__link').contains('Submariner add-ons').should('exist')
        clusterSetMethods.deleteClusterSet(clusterSetName)
    })
})

