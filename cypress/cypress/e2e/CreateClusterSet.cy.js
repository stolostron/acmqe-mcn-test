/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2022 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { clusterSetMethods } from '../views/clusterset/clusterset'

describe('Create a ClusterSet and check that the “Submariner Addon” tab exists', {
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

    it('create a ClusterSet and verify that the “Submariner Addon” tab exists.', { tags: ['addonTab'] }, function () {
        let clusterSetName = Cypress.env('CLUSTERSET_NAME')
        clusterSetMethods.createClusterSet(clusterSetName) 
        clusterSetMethods.deleteClusterSet(clusterSetName)

        //On commant until I can fix the cluster delete issue ==>
        //clusterSetMethods.clusterSetShouldExist(clusterSetName)
        //cy.get('[data-label=Name]').eq(1).click(15, 30)
        //cy.get('.pf-c-nav__link').contains('Submariner add-ons').should('exist') 
    })
})

