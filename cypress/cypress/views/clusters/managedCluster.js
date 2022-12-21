/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2021 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { acm23xheaderMethods, acmHeaderSelectors } from '../header'
import { commonElementSelectors } from '../common/commonSelectors'
import { clusterSetPages } from '../../views/clusterset/clusterset'

export const managedClustersSelectors = {
    elementTab: {
        clusters: 'Cluster list',
        clustersets: 'Cluster sets',
        clusterPools: 'Cluster pools',
        DiscoverClusters: 'Discovered clusters'
    }
}

export const clustersPages = {
    /**
     * verified that the DOM contains text "Cluster management"
     */
    shouldExist: () => {
        cy.contains(pageElements.h1, acmHeaderSelectors.leftNavigation.listItemsText.infrastructureText.clusters).should('contain', 'Cluster management')
    },

    goToClusterSet: () => {
        acm23xheaderMethods.goToClusters()
        cy.get(commonElementSelectors.elements.pageNavLink).filter(`:contains("${managedClustersSelectors.elementTab.clustersets}")`).click()
        clusterSetPages.shouldLoad()
    },

    // The function used to go to clusterset page when login as non-admin user.
    goToClusterSetsWithUser: () => {
        acm23xheaderMethods.goToClustersWithUser()
        cy.get(commonElementSelectors.elements.pageNavLink).filter(`:contains("${managedClustersSelectors.elementTab.clustersets}")`).click()
        clusterSetPages.shouldLoad()
    }
}
