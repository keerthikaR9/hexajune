---------------------------------------------------------------------------
-- File name   : XXOA_SIB_SELECT_TEST.sql
-- Author      : Keerthika
-- Date        : 22-Mar-2026
-- Description : Test SELECT script to validate cur_insert data
--               before running the full XXOA_AP_SIB_PAYMT_OUTB package
--
-- Usage       : Replace :P_BATCH with your actual Batch ID and run
--
-- Verify      :
--   1. DEBIT_ACCOUNT      - no special chars, max 34 chars
--   2. DEBIT_CURRENCY     - bank account currency
--   3. VALUE_DATE         - payment check date
--   4. CREDIT_ACCOUNT     - IBAN if available, else local account
--   5. TRANSFER_AMOUNT    - no comma, max 3 decimal places
--   6. CHARGETYPE         - should be OUR
--   7. TRANSFERPURPOSE    - from aisca.attribute6 if user selected
--   8. BENBANKSWIFTBICCODE- swift code max 11 chars
--   9. BENEFICIARYNAME    - vendor name, no special chars, max 35
--  10. FTCUSTREFID        - check number (payment voucher)
--  11. PAYMENTDETAILS     - invoice numbers separated by /  max 143
--  12. PAYMENTCURRENCY    - payment currency
--  13. BENADDRESSLINE1    - beneficiary address max 33 chars
--  14. BENADDRESSLINE2    - beneficiary address line 2 max 33 chars
--  15. BENADDRESSLINE3    - beneficiary city max 30 chars
--  16. BENBANKCOUNTRY     - beneficiary country code
--  17. SERVICECODE        - IFSC for INR, Sort Code for GBP
--  18. CHECKRUN_NAME      - payment batch name
--  19. BANK_NAME          - bank name (should contain SOHAR)
--  20. EXT_BANK_ACCOUNT_ID- should not be null
---------------------------------------------------------------------------

SELECT DISTINCT
  REGEXP_REPLACE(ba.BANK_ACCOUNT_NUM, '[^0-9A-Za-z]', '')               AS debit_account,
  ba.CURRENCY_CODE                                                        AS debit_currency,
  ch.check_date                                                           AS value_date,
  NVL(
    REGEXP_REPLACE(suppl_bank.iban_code, '[^0-9A-Za-z]', ''),
    suppl_bank.BeneficiaryAccountNumber
  )                                                                       AS credit_account,
  TO_CHAR(ch.AMOUNT, 'FM999999999999.990')                                AS transfer_amount,
  NULL                                                                    AS bulkcustrefid,
  'OUR'                                                                   AS chargetype,
  aisca.attribute6                                                        AS transferpurpose,
  SUBSTR(suppl_bank.BeneficiaryBankBICCode, 1, 11)                       AS benbankswiftbiccode,
  NULL                                                                    AS branchcode,
  NULL                                                                    AS bankcode,
  SUBSTR(REGEXP_REPLACE(suppl_bank.BeneficiaryName, '[^0-9A-Za-z ]', ' '), 1, 35) AS beneficiaryname,
  NULL                                                                    AS beneficiaryreference,
  NULL                                                                    AS bulkreference,
  ch.CHECK_NUMBER                                                         AS ftcustrefid,
  NULL                                                                    AS cbo,
  SUBSTR(
    (SELECT LISTAGG(REPLACE(inv.invoice_num, ',', ''), '/') WITHIN GROUP (ORDER BY inv.invoice_num)
     FROM   apps.ap_invoices_all inv,
            apps.ap_invoice_payments_all pay
     WHERE  inv.invoice_id = pay.invoice_id
     AND    pay.check_id   = ch.check_id),
    1, 143)                                                               AS paymentdetails,
  ch.CURRENCY_CODE                                                        AS paymentcurrency,
  NULL                                                                    AS benbranchname,
  NULL                                                                    AS benbankname,
  SUBSTR(suppl_bank.BeneficiaryAddress, 1, 33)                           AS benaddressline1,
  SUBSTR(suppl_bank.BeneficiaryAddressLine2, 1, 33)                      AS benaddressline2,
  SUBSTR(suppl_bank.BeneficiaryCity, 1, 30)                              AS benaddressline3,
  NULL                                                                    AS benbankaddressline3,
  suppl_bank.BeneficiaryAccountCountry                                   AS benbankcountry,
  NULL                                                                    AS notifyben,
  NULL                                                                    AS notifybenemail,
  NULL                                                                    AS notifybenchoice,
  NULL                                                                    AS benbranchaddress1,
  NULL                                                                    AS benbranchaddress2,
  NULL                                                                    AS benbranchaddresscity3,
  CASE
    WHEN ch.CURRENCY_CODE = 'INR' THEN suppl_bank.BeneficiaryIFSCCode
    WHEN ch.CURRENCY_CODE = 'GBP' THEN suppl_bank.BeneficiarySortCode
    ELSE NULL
  END                                                                     AS servicecode,
  NULL                                                                    AS servicefx,
  NULL                                                                    AS ratecode,
  NULL                                                                    AS numberofrecords,
  NULL                                                                    AS batchheaderid,
  DECODE(SUBSTR(TRIM(ch.checkrun_name), 1, 5), 'Quick', ch.check_id, ch.checkrun_id) AS checkrun_id,
  ch.checkrun_name                                                        AS checkrun_name,
  br.bank_name                                                            AS bank_name,
  br.BANK_HOME_COUNTRY                                                    AS bank_country,
  suppl_bank.ext_bank_account_id
FROM
  ap_checks_all                    ch,
  ce_bank_accounts                 ba,
  ce_bank_acct_uses_all            cbau,
  ce_bank_branches_v               br,
  ap_invoice_payments_all          aipa,
  ap.ap_invoices_all               aia,
  ap.ap_inv_selection_criteria_all aisca,
  iby_payments_all                 ipa,
  fnd_lookup_values                flv,
  (
    SELECT
      aps.vendor_name                                          AS BeneficiaryName,
      ass.ADDRESS_LINE1                                        AS BeneficiaryAddress,
      ass.ADDRESS_LINE2                                        AS BeneficiaryAddressLine2,
      ass.ADDRESS_LINE3                                        AS BeneficiaryAddressLine3,
      ass.CITY                                                 AS BeneficiaryCity,
      ass.STATE                                                AS BeneficiaryState,
      ass.ZIP                                                  AS BeneficiaryZip,
      hcp.email_address                                        AS BeneficiaryEmail,
      REGEXP_REPLACE(ieb.bank_account_num, '[^0-9A-Za-z]','') AS BeneficiaryAccountNumber,
      ieb.bank_account_name                                    AS BeneficiaryAccountName,
      ass.country                                              AS BeneficiaryAccountCountry,
      ieb.iban                                                 AS iban_code,
      ieb.ext_bank_account_id,
      ieb.currency_code                                        AS BeneficiaryAccountCurrency,
      ieb.attribute1                                           AS BeneficiaryBankBICCode,
      NVL(ieb.attribute3, ieb.attribute2)                      AS BeneficiaryIFSCCode,  -- IFSC for INR
      ieb.attribute4                                           AS BeneficiarySortCode,   -- Sort code for GBP
      party_bank.party_name                                    AS BeneficiaryBankName,
      branch_prof.organization_name                            AS BeneficiaryBranchName,
      iep.ext_payee_id,
      iep.payee_party_id
    FROM
      hz_parties               party_supp,
      ap_suppliers             aps,
      hz_party_sites           site_supp,
      ap_supplier_sites_all    ass,
      iby_external_payees_all  iep,
      iby_pmt_instr_uses_all   ipi,
      iby_ext_bank_accounts    ieb,
      hz_parties               party_bank,
      hz_parties               party_branch,
      hz_organization_profiles bank_prof,
      hz_organization_profiles branch_prof,
      hz_contact_points        hcp
    WHERE party_supp.party_id        = aps.party_id
    AND   party_supp.party_id        = site_supp.party_id
    AND   site_supp.party_site_id    = ass.party_site_id
    AND   ass.vendor_id              = aps.vendor_id
    AND   iep.payee_party_id         = party_supp.party_id
    AND   iep.party_site_id          = site_supp.party_site_id
    AND   iep.supplier_site_id       = ass.vendor_site_id
    AND   iep.ext_payee_id           = ipi.ext_pmt_party_id(+)
    AND   ipi.instrument_id(+)       = ieb.ext_bank_account_id
    AND   ieb.bank_id                = party_bank.party_id
    AND   ieb.branch_id              = party_branch.party_id
    AND   party_branch.party_id      = branch_prof.party_id
    AND   party_bank.party_id        = bank_prof.party_id
    AND   site_supp.party_site_id    = hcp.owner_table_id(+)
    AND   hcp.contact_point_type(+)  = 'EMAIL'
    AND   hcp.status(+)              = 'A'
    AND   hcp.owner_table_name(+)    = 'HZ_PARTY_SITES'
    AND   hcp.primary_flag(+)        = 'Y'
  ) suppl_bank
WHERE ch.ce_bank_acct_use_id            = cbau.bank_acct_use_id
AND   cbau.bank_account_id              = ba.bank_account_id
AND   ba.bank_branch_id                 = br.branch_party_id
AND   ch.check_id                       = aipa.check_id
AND   ch.checkrun_id                    = aisca.checkrun_id(+)
AND   aia.invoice_id                    = aipa.invoice_id
AND   ch.payment_id                     = ipa.payment_id(+)
AND   ipa.payments_complete_flag(+)     = 'Y'
AND   suppl_bank.payee_party_id(+)      = ipa.payee_party_id
AND   suppl_bank.ext_bank_account_id(+) = ch.external_bank_account_id
AND   suppl_bank.ext_payee_id(+)        = ipa.ext_payee_id
AND   ch.attribute_category            IS NULL
AND   flv.lookup_type                   = 'XXOA_SIB_EBANKING_BANK_ACCOUNT'
AND   flv.enabled_flag                  = 'Y'
AND   UPPER(flv.attribute_category)     = UPPER('EBanking Bank Accounts')
AND   UPPER(br.bank_name)               = UPPER(flv.attribute1)
AND   UPPER(ch.bank_account_name)       = UPPER(flv.attribute2)
AND   flv.language                      = 'US'
AND   ch.status_lookup_code             = 'NEGOTIABLE'
AND   DECODE(SUBSTR(TRIM(ch.checkrun_name), 1, 5), 'Quick', ch.check_id, ch.checkrun_id) = :P_BATCH
AND   ch.org_id                         = cbau.org_id
AND   ch.org_id                         = aipa.org_id
AND   UPPER(br.bank_name)               LIKE '%SOHAR%';





SELECT DISTINCT
  REGEXP_REPLACE(ba.BANK_ACCOUNT_NUM, '[^0-9A-Za-z]', '')  AS debit_account,
  ba.CURRENCY_CODE                                          AS debit_currency,
  ch.check_date                                             AS value_date,
  NVL(
    REGEXP_REPLACE(suppl_bank.iban_code, '[^0-9A-Za-z]', ''),
    suppl_bank.BeneficiaryAccountNumber
  )                                                         AS credit_account,
  TO_CHAR(ch.AMOUNT, 'FM999999999999.990')                  AS transfer_amount,
  suppl_bank.BeneficiaryName                                AS beneficiaryname,
  suppl_bank.BeneficiaryBankBICCode                         AS swift_code,
  ch.checkrun_name,
  br.bank_name,
  ch.bank_account_name,
  suppl_bank.ext_bank_account_id
FROM
  ap_checks_all                    ch,
  ce_bank_accounts                 ba,
  ce_bank_acct_uses_all            cbau,
  ce_bank_branches_v               br,
  ap_invoice_payments_all          aipa,
  ap.ap_invoices_all               aia,
  ap.ap_inv_selection_criteria_all aisca,
  iby_payments_all                 ipa,
  (
    SELECT
      aps.vendor_name                                          AS BeneficiaryName,
      ass.ADDRESS_LINE1                                        AS BeneficiaryAddress,
      ass.country                                              AS BeneficiaryAccountCountry,
      ieb.iban                                                 AS iban_code,
      REGEXP_REPLACE(ieb.bank_account_num, '[^0-9A-Za-z]','') AS BeneficiaryAccountNumber,
      ieb.ext_bank_account_id,
      ieb.attribute1                                           AS BeneficiaryBankBICCode,
      NVL(ieb.attribute3, ieb.attribute2)                      AS BeneficiaryIFSCCode,
      iep.ext_payee_id,
      iep.payee_party_id
    FROM
      hz_parties               party_supp,
      ap_suppliers             aps,
      hz_party_sites           site_supp,
      ap_supplier_sites_all    ass,
      iby_external_payees_all  iep,
      iby_pmt_instr_uses_all   ipi,
      iby_ext_bank_accounts    ieb,
      hz_parties               party_bank,
      hz_parties               party_branch,
      hz_organization_profiles bank_prof,
      hz_organization_profiles branch_prof
    WHERE party_supp.party_id        = aps.party_id
    AND   party_supp.party_id        = site_supp.party_id
    AND   site_supp.party_site_id    = ass.party_site_id
    AND   ass.vendor_id              = aps.vendor_id
    AND   iep.payee_party_id         = party_supp.party_id
    AND   iep.party_site_id          = site_supp.party_site_id
    AND   iep.supplier_site_id       = ass.vendor_site_id
    AND   iep.ext_payee_id           = ipi.ext_pmt_party_id(+)
    AND   ipi.instrument_id(+)       = ieb.ext_bank_account_id
    AND   ieb.bank_id                = party_bank.party_id
    AND   ieb.branch_id              = party_branch.party_id
    AND   party_branch.party_id      = branch_prof.party_id
    AND   party_bank.party_id        = bank_prof.party_id
  ) suppl_bank
WHERE ch.ce_bank_acct_use_id            = cbau.bank_acct_use_id
AND   cbau.bank_account_id              = ba.bank_account_id
AND   ba.bank_branch_id                 = br.branch_party_id
AND   ch.check_id                       = aipa.check_id
AND   ch.checkrun_id                    = aisca.checkrun_id(+)
AND   aia.invoice_id                    = aipa.invoice_id
AND   ch.payment_id                     = ipa.payment_id(+)
AND   ipa.payments_complete_flag(+)     = 'Y'
AND   suppl_bank.payee_party_id(+)      = ipa.payee_party_id
AND   suppl_bank.ext_bank_account_id(+) = ch.external_bank_account_id
AND   suppl_bank.ext_payee_id(+)        = ipa.ext_payee_id
AND   ch.attribute_category            IS NULL
AND   ch.status_lookup_code             = 'NEGOTIABLE'
AND   ch.org_id                         = cbau.org_id
AND   ch.org_id                         = aipa.org_id
AND   DECODE(SUBSTR(TRIM(ch.checkrun_name), 1, 5), 'Quick', ch.check_id, ch.checkrun_id) = 34490446
AND   UPPER(br.bank_name)               LIKE '%SOHAR%'
AND   EXISTS (
      SELECT 1
      FROM   fnd_lookup_values flv
      WHERE  flv.lookup_type           = 'XXOA_SIB_EBANKING_BANK_ACCOUNT'
      AND    flv.enabled_flag          = 'Y'
      AND    UPPER(flv.attribute_category) = UPPER('Ebanking Bank Accounts')
      AND    UPPER(br.bank_name)       = UPPER(flv.attribute1)
      AND    UPPER(ch.bank_account_name) = UPPER(flv.attribute2)
      AND    flv.language              = 'US');
