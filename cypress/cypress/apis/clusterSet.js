/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2022 Red Hat, Inc.
 ****************************************************************************** */
/// <reference types="cypress" />

import * as constants from "../support/constants"

var headers = {
    "Content-Type": "application/json",
    Accept: "application/json"
}

/**
* Get the clusterset info
* @param {string} clusterSet
* @returns {resp}
*/
export const getClusterSet = (clusterSet) => {
    headers.Authorization = `Bearer ${Cypress.env("token")}`
    let options = {
        method: "GET",
        url:
            constants.apiUrl +
            constants.ocm_cluster_api_v1beta1_path +
            constants.managedclustersets_path +
            '/' + clusterSet,
        headers: headers,
        failOnStatusCode: false
    }
    return cy.request(options)
        .then(resp => {
            return resp
        })
}
