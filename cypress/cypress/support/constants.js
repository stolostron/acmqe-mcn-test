/** *****************************************************************************
 * Licensed Materials - Property of Red Hat, Inc.
 * Copyright (c) 2021 Red Hat, Inc.
 ****************************************************************************** */
/// <reference types="cypress" />

// API Endpoint

// OCP API PATH
export const ocm_cluster_api_v1_path = "/apis/cluster.open-cluster-management.io/v1"
export const ocm_addon_api_path = "/apis/addon.open-cluster-management.io/v1alpha1"
export const ocm_cluster_api_v1beta1_path = "/apis/cluster.open-cluster-management.io/v1beta1"
export const ocm_cluster_api_v1beta2_path = "/apis/cluster.open-cluster-management.io/v1beta2"
export const ocm_agent_api_path = "/apis/agent.open-cluster-management.io/v1"

// Hive API PATH
export const hive_namespaced_api_path = "/apis/hive.openshift.io/v1/namespaces/"
export const hive_api_path = "/apis/hive.openshift.io/v1"

// Kubernetes API PATH
export const rbac_api_path = "/apis/rbac.authorization.k8s.io/v1"
export const user_api_path = "/apis/user.openshift.io/v1"

export const managedclustersets_path = "/managedclustersets"
export const clusterpools_path = "/clusterpools"
export const clusterclaims_path = "/clusterclaims"
export const machinepools_path = "/machinepools"

// Ansible API PATH
export const jobtemplate_api_path = "/api/v2/job_templates/"
export const inventory_api_path = "/api/v2/inventories/"
export const project_api_path = "/api/v2/projects/"

// API URL
export const apiUrl = (Cypress.config().baseUrl.startsWith("https://multicloud-console.apps")) ? Cypress.config().baseUrl.replace("multicloud-console.apps", "api") + ":6443" : Cypress.config().baseUrl.replace("console-openshift-console.apps", "api") + ":6443"
export const ocpUrl = (Cypress.config().baseUrl.startsWith("https://multicloud-console.apps")) ? Cypress.config().baseUrl.replace("multicloud-console.apps", "console-openshift-console.apps") : Cypress.config().baseUrl
export const prometheusUrl = (Cypress.config().baseUrl.startsWith("https://multicloud-console.apps")) ? Cypress.config().baseUrl.replace("multicloud-console.apps", "prometheus-k8s-openshift-monitoring.apps") : Cypress.config().baseUrl.replace("console-openshift-console.apps", "prometheus-k8s-openshift-monitoring.apps")
export const authUrl = (Cypress.config().baseUrl.startsWith("https://multicloud-console.apps")) ? Cypress.config().baseUrl.replace("multicloud-console.apps", "oauth-openshift.apps") : Cypress.config().baseUrl.replace("console-openshift-console.apps", "oauth-openshift.apps")
