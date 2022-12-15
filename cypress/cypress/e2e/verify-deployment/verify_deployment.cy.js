/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2022 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { clusterSetMethods } from '../../views/clusterset/clusterset'

describe('clusterSet - Action', {
    tags: ['@', '@e2e'],
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

    // Cluster clusterSet
    it('verify that a cluster set with deployment of submariner is exists.', { tags: ['clusterset', 'noga'] }, function () {
        let clusterSetName = Cypress.env('CLUSTERSET_NAME')
        clusterSetMethods.clusterSetShouldExist(clusterSetName)
        cy.get('[data-label=Name]').click(15, 30, {multiple: true})
        cy.get('.pf-c-nav__link').eq(12).click()
    })

    it('test the Connection status label', { tags: ['clusterset', 'Connection'] }, function () {
        let len = cy.get('[data-label="Connection status"]')

        var size = Object.keys(len).length -1;

        for (let i = 1; i < size -1; i++) {
            cy.get('[data-label="Connection status"]').eq(i).click(40, 30).should('have.text', 'Healthy')
            cy.get('.pf-c-popover__content').contains('established').should('exist').and('be.visible')
        }
        cy.get('[data-label="Connection status"]').eq(-1).click(40, 30 , {multiple: true})
    })

    it('test the Agent status label', { tags: ['clusterset', 'Agent'] }, function () {
        let len = cy.get('[data-label="Agent status"]')

        var size = Object.keys(len).length -1;

        for (let i = 1; i < size -1; i++) {
            cy.get('[data-label="Agent status"]').eq(i).click(40, 30).should('have.text', 'Healthy')
            cy.get('.pf-c-popover__content').contains('is deployed on managed cluster').should('exist').and('be.visible')
        }
        cy.get('[data-label="Agent status"]').eq(-1).click(40, 30 , {multiple: true})
    })

    it('test the Gateway nodes labeled label', { tags: ['clusterset', 'Gateway'] }, function () {
        let len = cy.get('[data-label="Gateway nodes labeled"]')

        var size = Object.keys(len).length -1;

        for (let i = 1; i < size -1; i++) {
            cy.get('[data-label="Gateway nodes labeled"]').eq(i).click(40, 30).should('have.text', 'Nodes labeled')
            cy.get('.pf-c-popover__content').contains('are labeled with "submariner.io/gateway').should('exist').and('be.visible')
        }
        cy.get('[data-label="Gateway nodes labeled"]').eq(-1).click(40, 30 , {multiple: true})
    })
        
})

