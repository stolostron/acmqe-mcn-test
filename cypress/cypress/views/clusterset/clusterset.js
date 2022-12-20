/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2021 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { acmHeaderSelectors } from '../header'
import { commonElementSelectors, commonPageMethods } from '../common/commonSelectors'

import { clustersPages } from '../clusters/managedCluster'

/**
 * This object contains the group of selector that are part of clusterSet
 */
export const clusterSetPageSelector = {
    elementText: {
        createClusterSet: 'Create cluster set',
        deleteClusterSets: 'Delete cluster sets'
    }
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
}
