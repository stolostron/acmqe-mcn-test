/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2021 Red Hat, Inc.
 ****************************************************************************** */

/// <reference types="cypress" />

import { clusterSetMethods } from '../../../views/clusterset/clusterset'

export const submarinerClusterSetMethods = {

    // The function verifies that submariner deployment exists.
    submarinerClusterSetShouldExist: (clusterSetName) => {
        clusterSetMethods.clusterSetShouldExist(clusterSetName)
        cy.get('[data-label=Name]').eq(1).click(15, 30)
        cy.get('.pf-c-nav__link').contains('Submariner add-ons').click()
    },
}


