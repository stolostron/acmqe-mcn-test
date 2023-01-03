/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2022 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { acmHeaderSelectors } from '../header'
import { commonElementSelectors, commonPageMethods } from '../common/commonSelectors'

import { clustersPages } from '../clusters/managedCluster'
import { getClusterSet } from '../../apis/clusterSet'

/**
 * This object contains the group of selector that are part of clusterSet
 */
export const clusterSetPageSelector = {
    elementText: {
        createClusterSet: 'Create cluster set',
        deleteClusterSets: 'Delete cluster sets'
    },
    button: {
        createClusterSet: 'button[id="createClusterSet"]',
        deleteClusterSets: 'li[id="deleteClusterSets"]',
    },
    msg: {
        noClusterSet: "You don't have any cluster sets",
        createSuccess: "Cluster set successfully created",
    },
    createClusterSet: {
        title: "Create cluster set",
        clusterSetName: "#clusterSetName",
    },
}

/**
 * This object contains the group of methods that are part of clusterSet page
 */
export const clusterSetMethods = {

    // The function used to make sure the clusterset was exists
    clusterSetShouldExist: (clusterSet, role) => {
        clusterSetPages.goToClusterSetTable(role)
        commonPageMethods.resourceTable.rowShouldExist(clusterSet)
    },

    /**
     * Create a clusterset via the UI
     * @param {*} clusterSet the clusterset name
     */
        createClusterSet: (clusterSet) => {
            // if the clusterset doesn't exist, let's create it. Otherwise we won't bother.
            getClusterSet(clusterSet).then(resp => {
                if (resp.status == 404) {
                    clusterSetPages.goToCreateClusterSet()
                    cy.get(clusterSetPageSelector.createClusterSet.clusterSetName).type(clusterSet)
                    cy.get(commonElementSelectors.elements.submit, { timeout: 2000 }).click()
                    cy.get(commonElementSelectors.elements.dialog, { timeout: 2000 })
                        .contains(clusterSetPageSelector.msg.createSuccess)
                        .then(() =>
                            cy.contains(commonElementSelectors.elements.button, commonElementSelectors.elementsText.close).click())
                }
            })
        },
    
        /**
         * Delete a clusterset via the UI
         * @param {*} clusterSet the clusterset name
         */
        deleteClusterSet: (clusterSet, cancel) => {
            getClusterSet(clusterSet).then(resp => {
                if (resp.status == 200) {
                    clusterSetMethods.clusterSetShouldExist(clusterSet)
                    clusterSetPages.goToDeleteClusterSet(clusterSet)
                    commonPageMethods.modal.confirmAction(clusterSet)
                    if (!cancel) {
                        cy.get(commonElementSelectors.elements.submit, { timeout: 2000 }).click()
                        cy.log('Make sure the clusterset should be deleted')
                        cy.waitUntil(() => {
                            return getClusterSet(clusterSet).then(resp => {
                                return (resp.status == 404)
                            })
                        },
                            {
                                interval: 2 * 1000,
                                timeout: 20 * 1000
                            })
                    } else {
                        cy.get(commonElementSelectors.elements.dialog, { withinSubject: null })
                            .contains(commonElementSelectors.elements.button, commonElementSelectors.elementsText.cancel)
                            .click({ timeout: 20000 })
                        getClusterSet(clusterSet).then((resp) => {
                            expect(resp.status).to.be.eq(200)
                        })
                    }
                }
            })
        },
}

/**
 * This object contains the group of page that are part of clusterSet page
 */
export const clusterSetPages = {
    shouldLoad: () => {
        cy.get(commonElementSelectors.elements.pageClassKey, { timeout: 10000 }).should('contain', acmHeaderSelectors.leftNavigation.listItemsText.infrastructureText.clusters)
        cy.url().should('include', '/infrastructure/clusters/sets', { timeout: 10000 })
        cy.get(commonElementSelectors.elements.button, { timeout: 10000 }).should('contain', clusterSetPageSelector.elementText.createClusterSet)
        cy.wait(1000)
    },

    goToClusterSetTable: (role) => {
        switch (role) {
            case 'view':
            case 'bind':
                clustersPages.goToClusterSetsWithUser()
                break
            case 'admin':
            default:
                clustersPages.goToClusterSet()
                break
        }
    },

    goToCreateClusterSet: () => {
        clustersPages.goToClusterSet()
        cy.get(commonElementSelectors.elements.mainSection).then(($body) => {
            if (!$body.text().includes(clusterSetPageSelector.msg.noClusterSet)) {
                cy.get(clusterSetPageSelector.button.createClusterSet, { timeout: 3000 })
                    .should('exist')
                    .click()
            }
            else {
                cy.contains(commonElementSelectors.elements.button, clusterSetPageSelector.elementText.createClusterSet).click()
            }
        })
    },

    goToDeleteClusterSet: (clusterSet) => {
        commonPageMethods.resourceTable.openRowMenu(clusterSet)
        cy.get(clusterSetPageSelector.tableRowOptionsMenu.deleteClusterSet).click()
    },
}
