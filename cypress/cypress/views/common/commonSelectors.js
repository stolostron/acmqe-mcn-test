/// <reference types="cypress"/>

export const commonElementSelectors = {
    elements: {
        a: 'a',
        h1: 'h1',
        h2: 'h2',
        h4: 'h4',
        tr: 'tr',
        td: 'td',
        tbody: 'tbody',
        input: 'input',
        button: 'button',
        class: 'class',
        option: 'option',
        checkbox: 'input[class="pf-c-check__input"]',
        dialog: 'div[role="dialog"]',
        delete: '#delete',
        actionsButton: '#toggle-id',
        checkAll: '[name="check-all"]',
        selectMenuItem: ".pf-c-select__menu-item",
        pageMenu: '.pf-c-page__main > :nth-child(2)',
        deleteTableRowButtonClass: 'button[class="pf-c-dropdown__toggle pf-m-plain"]',
        pageClassKey: ".pf-c-page",
        pageNavLink: ".pf-c-nav__link",
        mainSection: '.pf-c-page__main-section',
        dialogPageCover: ".pf-l-bullseye",
        buttonClassKey: ".pf-c-empty-state__primary > .pf-c-button",
        disabledButton: "pf-m-aria-disabled",
        pageSearch: 'input[aria-label="Search input"]',
        resetSearch: 'button[aria-label="Reset"]',
        dropDownToggleButton: 'button[aria-label="Options menu"]',
        dropDownMenu: '.pf-c-dropdown__menu',
        dropDownMenuItem: 'button.pf-c-dropdown__menu-item',
        xButton: 'button[aria-label="Close"]',
        lable: 'div[class="pf-c-form__group-label"]',
        currentTabClass: 'a[class="pf-c-nav__link pf-m-current"]',
        tabClass: 'a[class="pf-c-nav__link"]',
        radioInput: 'div[class="pf-c-radio"]',
        chipText: '.pf-c-chip__text',
        emptyContent: '.pf-c-empty-state__content',
        emptyBody: '.pf-c-empty-state__body',
        toolbarContentSection: '.pf-c-toolbar__content-section',
        title: '.pf-c-title',
        table: 'table',
        firstRowIndex: '1',
        submit: 'button[type="submit"]'
    },
    elementsText: {
        next: 'Next',
        add: 'Add',
        actions: 'Actions',
        approve: 'Approve',
        approveAll: 'Approve all hosts',
        create: 'Create',
        cancel: 'Cancel',
        close: 'Close',
        import: 'Import',
        save: 'Save',
        InstallCluster: 'Install cluster',
        delete: 'Delete',
        review: 'Review',
        close: 'Close',
        remove: 'Remove',
        noResult: 'No results found',
        forbindden: 'Forbidden',
        forbiddenMsg: 'You are not authorized to complete this action. See your cluster administrator for role-based access control information.',
    },
    alerts: {
        dangerAlert: '[aria-label="Danger Alert"]',
        alertTitle: '.pf-c-alert__title',
        alertIcon: '.pf-c-alert__icon',
        alertAction: '.pf-c-alert__action',
        alertDescrition: '.pf-c-alert__description'
    }
}

export const commonPageMethods = {
    resourceTable: {
        shouldExist: () => cy.get(commonElementSelectors.elements.table, { timeout: 20000 }).should('exist'),
        shouldNotExist: () => cy.get(commonElementSelectors.elements.table, { timeout: 20000 }).should('not.exist'),
        rowShouldExist: function (name) {
            this.searchTable(name)
            cy.get(`tr > td a`, { timeout: 30000 })
                .contains(name, { timeout: 30000 })
                .should('exist')
        },
        rowShouldNotExist: function (name, timeout, disableSearch) {
            !disableSearch && this.searchTable(name)
            cy.get(`tr[data-ouia-component-id="${name}"]`, { timeout: timeout || 30000 }).should('not.exist')
        },
        getRowByIndex: function (rowIndex) {
            return cy.get(commonElementSelectors.elements.table, { timeout: 1000 })
                .find(commonElementSelectors.elements.tr).eq(rowIndex)
        },
        checkIfRowExistsByName: function (name) {
            this.searchTable(name)
            return cy.wait(500).get(commonElementSelectors.elements.table).then($table => {
                return cy.wrap($table.text().includes(name))
            })
        },
        openRowMenu: (name) => {
            cy.log(name)
            cy.get(`#${name}-actions`).click()
            cy.wait(1500).get('div[triggerclassname="overflow-permission-tooltip"]', { timeout: 2000 }).should('not.exist')
        },

        clickInfraEnvActionButton: () => { cy.get(commonElementSelectors.elements.button).contains("Actions").click({ force: true }) },
        menuClickEdit: () => cy.get('button[data-table-action="table.actions.connection.edit"]').click(),
        menuClickEditLabels: () => cy.get('button[data-table-action="table.actions.cluster.edit.labels"]').click(),
        menuClickDelete: () => cy.get('button[data-table-action="table.actions.connection.delete"]').click(),
        menuClickDeleteType: (type) => cy.get(`button[data-table-action="table.actions.${type}.delete"]`).click(),
        menuClickDestroy: () => cy.get('button[data-table-action="table.actions.cluster.destroy"]').click(),
        menuClickDetach: () => cy.get('button[data-table-action="table.actions.cluster.detach"]').click(),
        clearSearch: () => cy.get(commonElementSelectors.elements.pageSearch, { timeout: 10 * 1000 }).clear(),
        searchTable: (name) => {
            commonPageMethods.resourceTable.clearSearch();
            cy.get(commonElementSelectors.elements.pageSearch).type(name)
            cy.wait(2 * 1000)
        },
        rowShouldToggle: function (name) {
            cy.get('#pf-c-page').then(page => {
                if (page.find(commonElementSelectors.elements.pageSearch, { timeout: 15000 }).length > 0) {
                    cy.get(commonElementSelectors.elements.pageSearch).clear({ force: true })
                    cy.get(commonElementSelectors.elements.pageSearch).type(name)
                }
            })
            cy.get(`tr[data-row-name="${name}"]`).get('input[name="tableSelectRow"]').click({ force: true })
        },
        rowCount: () =>
            cy.get("table", { timeout: 30 * 1000 }).then($table => {
                return $table.find("tbody").find("tr").length;
            }),
        rowExist: (name) => cy.get(`tr[data-ouia-component-id="${name}"]`).should('exist'),
        rowValue: (name, colume, value, span) => {
            if (span) cy.get(`tr[data-ouia-component-id="${name}"] td[data-label="${colume}"] > span`).contains(`${value}`).should('exist')
            else cy.get(`tr[data-ouia-component-id="${name}"] td[data-label="${colume}"]`).contains(`${value}`).should('exist')
        },
        buttonShouldClickable: (text, href) => {
            if (href) {
                cy.waitUntil(() => {
                    return cy.get('a').contains(text, { timeout: 20000 }).then($button => {
                        return ($button.attr('aria-disabled') == 'false')
                    })
                },
                    {
                        errorMsg: "wait for hyperlink to be clickable",
                        interval: 4 * 1000, // check every 4s
                        timeout: 60 * 1000 // wait for 60s
                    })
            }
            else {
                cy.waitUntil(() => {
                    return cy.get(text).then($button => {
                        return ($button.attr('aria-disabled') == 'false')
                    })
                },
                    {
                        errorMsg: "wait for button to be clickable",
                        interval: 4 * 1000, // check every 4s
                        timeout: 60 * 1000 // wait for 60s
                    })
            }
        }
    },
    waitforDialogClosed: () => {
        cy.waitUntil(() => {
            return cy.get('body').then(body => {
                console.log('The length of dialog is:', body.find(commonElementSelectors.elements.dialog).length)
                return (body.find(commonElementSelectors.elements.dialog).length <= 1)
            })
        },
            {
                errorMsg: "wait for dialog closed",
                interval: 500,
                timeout: 5000
            })
    },
    modal: {
        getDialogElement: () => {
            return cy.get(commonElementSelectors.elements.dialog, { withinSubject: null })
        },
        shouldBeOpen: () => cy.get(commonElementSelectors.elements.dialog, { withinSubject: null }).should('exist'),
        shouldBeClosed: () => cy.get('.pf-c-modal-box pf-m-warning pf-m-md', { withinSubject: null }).should('not.exist'),
        clickDanger: (text) => cy.get(commonElementSelectors.elements.dialog, { withinSubject: null }).contains('button', text).click(),
        clickPrimary: () => cy.get(commonElementSelectors.elements.dialog, { withinSubject: null }).contains('button', 'Cancel').click({ timeout: 20000 }),
        clickSecondaryClose: () => cy.get('button[aria-label="Close"]', { withinSubject: null }).click(),
        confirmAction: text => cy.get('#confirm', { withinSubject: null }).type(text)
    },
    actionMenu: {
        checkActionByOption: (action, exists) => {
            if (exists) cy.get(commonElementSelectors.elements.dropDownMenu).should('contain', action)
            else cy.get(commonElementSelectors.elements.dropDownMenu).should('not.contain', action)
        },
        clickActionByOption: (name) => {
            commonPageMethods.resourceTable.buttonShouldClickable(name, commonElementSelectors.elements.a)
            cy.contains(commonElementSelectors.elements.a, name).click({ timeout: 20000 })
        },
        clickActionButton: (name) => {
            cy.get(`button[id="${name}-actions"]`).click()
        },
    },
    notification: {
        shouldExist: type =>
            cy.get(`.pf-c-alert.pf-m-${type}`, { timeout: 40 * 1000 })
                .should("exist"),
        shouldSuccess: () =>
            cy.contains(".pf-c-alert__title", "Success").should("be.visible")
    }
}
