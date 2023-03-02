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

    // The function adds the AWS an GCP clusters to the cluster set.
    // start position: from the 'Cluster set' list.
    manageClusterSet: (clusterSetName) => {
        cy.get('[data-label="Name"]').contains(clusterSetName).click()
        cy.get('#clusters').contains('Go to Managed clusters').click()
        cy.wait(100)
        cy.get('.pf-c-empty-state__primary > .pf-c-button').click()
        cy.get('[data-label="Name"]').each(($el, index) => {
            if (index > 0) {
                if (!$el.text().includes('local-cluster')){// skip the local
                    cy.get('[data-label=Infrastructure]').eq(index).then(($platform) => { // get cluster patform
                        if ($platform.text().includes('Google') || $platform.text().includes('Amazon')){
                            cy.get('[type="checkbox"]').eq(index).click()
                        }
                    })
                }
            }
        })
        cy.get('#save').click()//review
    },


    // The function checks if the current data label exists and contains the correct message
    testTheDataLabel: (dataLabel, textToHave, messageToHave) => {
        cy.get(dataLabel).each(($el, index) => {
            if (index > 0){
                cy.wrap($el).click(40, 30).should('have.text', textToHave)
                cy.get('.pf-c-popover__content').contains(messageToHave).should('exist').and('be.visible')
            }
        })
        cy.get(dataLabel).eq(-1).click(40, 30)
    },

    // The function checks if submariner was deployed properly
    isDeploy: (clusterset_name, cluster_aws, cluster_gcp) => {
        // Go to the submariner adds-on page
        clusterSetMethods.clusterSetShouldExist(clusterset_name)
        cy.get('[data-label=Name]').eq(1).click(15, 30)
        cy.get('.pf-c-nav__link').contains('Submariner add-ons').click()
                
        // Wait until submariner installation on the aws cluster is completed 
        cy.get('tr').contains(cluster_aws).then(($aws) => {
            cy.wrap($aws).closest('tr').then(($tr) => {
                cy.wrap($tr).waitUntilContains('[data-label="Connection status"]','Healthy', { timeout: 300000, interval: 3000 }) 
            })
        })
        cy.get('tr').contains(cluster_gcp).then(($gcp) => {
            cy.wrap($gcp).closest('tr').then(($tr) => {
                cy.wrap($tr).waitUntilContains('[data-label="Connection status"]','Healthy', { timeout: 300000, interval: 3000 }) 
            })
        })

        // Login to the GCP Managed Clutser (cluster_gcp) and execute the following commands on this cluster
        cy.managedClusterLogin(Cypress.env(cluster_aws + '_api'), Cypress.env(cluster_aws + '_user'), Cypress.env(cluster_aws + '_pwd'))

        cy.exec('oc -n default create deployment nginx --image=nginxinc/nginx-unprivileged:stable-alpine', {failOnNonZeroExit: false, timeout: 15000})
        cy.exec('oc -n default expose deployment nginx --port=8080', {failOnNonZeroExit: false, timeout: 15000})
        cy.exec('subctl export service --namespace default nginx', {failOnNonZeroExit: false, timeout: 15000}) // Should be replaced by ocp manifest
        cy.exec("oc -n default run tmp-shell --rm -i --tty --image quay.io/submariner/nettest -- /bin/bash -c 'sleep 40 && curl nginx.default.svc.clusterset.local:8080'",
         {failOnNonZeroExit: false, timeout: 15000}).then(output => {
            //cy.wait(50000)
            Object.entries(output).forEach((line) => {
                cy.log(line)
              })
         })
         
            // .its('stdout')
            // .should('contain','<html>')
            // .should('contain','Welcome to nginx!')
    },
}


