CREATE OR REPLACE PACKAGE BODY XXOA_AP_SIB_PAYMT_OUTB
AS
  ---------------------------------------------------------------------------
  -- 2026, Hexaware Technologies. All rights reserved.
  ---------------------------------------------------------------------------
  -- File name                : XXOA_AP_SIB_PAYMT_OUTB
  -- Author                   : Keerthika
  -- Date                     : 22-Mar-2026
  -- Language                 : English
  -- Module                   : AP
  -- Doc Ref(s)               :
  --
  -- Client                   : Oman Air
  --
  -- Description              : Package for Generating Payment details file and
  --                            transfer to the Bank server for Bank Sohar (SIB)
  --
  -- Change History Information
  -- --------------------------
  -- Version  Date         Author        Change Reference / Description
  -- -------  -----------  ------------  --------------------------------
  -- 1.0      22-Mar-2026  Keerthika     Initial Version
  ---------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- PROCEDURE: outbound_validation
  -- Main orchestrator. Inserts data into staging, runs validations,
  -- generates CSV file, submits SFTP concurrent request.
  ----------------------------------------------------------------------------
  PROCEDURE outbound_validation(
      errbuf  OUT VARCHAR2,
      retcode OUT VARCHAR2,
      P_BATCH IN  NUMBER
  )
  IS
    ---------------------------------------------------------------------------
    -- Cursor: Distinct payment batches in staging (not yet processed)
    ---------------------------------------------------------------------------
    CURSOR rec_payment_batch_cur IS
      SELECT DISTINCT CHECKRUN_NAME,
             DECODE(BENBANKCOUNTRY, 'OM', 'OM', 'FC') BEN_NATIONALITY
      FROM   XXOA_PAYMENT_OU_SIB_STG
      WHERE  CHECKRUN_ID = P_BATCH
      AND    FILE_NAME  IS NULL;

    ---------------------------------------------------------------------------
    -- Cursor: CSV header row for the file
    -- File name format:
    -- <CustRef>_<EntityRef>_<ApplicantRef>_<AccountingType>_<ProcessingType>_BS_<DateTime>.csv
    -- TODO: Replace placeholders once Bank Sohar confirms the reference values
    ---------------------------------------------------------------------------
    CURSOR csv_header_cur(p_request_id NUMBER) IS
      SELECT DISTINCT
             'CUSTREF'           AS customer_reference,   -- TODO: Replace with actual Customer Reference from Bank
             'ENTITYREF'         AS entity_reference,     -- TODO: Replace with actual Entity Reference from Bank
             'APPREF'            AS applicant_reference,  -- TODO: Replace with actual Applicant Reference from Bank
             'MDMC'              AS accounting_type,      -- TODO: Business to confirm MDMC or SDMC
             'NSTP'              AS processing_type,      -- TODO: Business to confirm STP or NSTP
             CHECKRUN_NAME
      FROM   XXOA_PAYMENT_OU_SIB_STG
      WHERE  CHECKRUN_ID  = P_BATCH
      AND    REQUEST_ID   = p_request_id
      AND    NVL(TO_CHAR(RETCODE), '0') <> '1';

    ---------------------------------------------------------------------------
    -- Cursor: Column header row written as first line inside the CSV
    ---------------------------------------------------------------------------
    CURSOR csv_col_header_cur IS
      SELECT 'DebitAccount'          || CHR(44) ||
             'DebitCurrency'         || CHR(44) ||
             'ValueDate'             || CHR(44) ||
             'CreditAccount'         || CHR(44) ||
             'TransferAmount'        || CHR(44) ||
             'BulkCustRefId'         || CHR(44) ||
             'ChargeType'            || CHR(44) ||
             'TransferPurpose'       || CHR(44) ||
             'BenBankSwiftBICCode'   || CHR(44) ||
             'BranchCode'            || CHR(44) ||
             'BankCode'              || CHR(44) ||
             'BeneficiaryName'       || CHR(44) ||
             'BeneficiaryReference'  || CHR(44) ||
             'BulkReference'         || CHR(44) ||
             'FTCustRefId'           || CHR(44) ||
             'CBO'                   || CHR(44) ||
             'PaymentDetails'        || CHR(44) ||
             'PaymentCurrency'       || CHR(44) ||
             'BenBranchName'         || CHR(44) ||
             'BenBankName'           || CHR(44) ||
             'BenAddressLine1'       || CHR(44) ||
             'BenAddressLine2'       || CHR(44) ||
             'BenAddressLine3'       || CHR(44) ||
             'BenBankAddressLine1'   || CHR(44) ||
             'BenBankCountry'        || CHR(44) ||
             'NotifyBen'             || CHR(44) ||
             'NotifyBenEmail'        || CHR(44) ||
             'NotifyBenChoice'       || CHR(44) ||
             'BenBranchAddress1'     || CHR(44) ||
             'BenBranchAddress2'     || CHR(44) ||
             'BenBranchAddressCity3' || CHR(44) ||
             'ServiceCode'           || CHR(44) ||
             'ServiceFX'             || CHR(44) ||
             'RateCode'              || CHR(44) ||
             'NumberOfRecords'       || CHR(44) ||
             'BatchHeaderID'         || CHR(44) ||
             'R1' || CHR(44) || 'R2' || CHR(44) || 'R3' || CHR(44) ||
             'R4' || CHR(44) || 'R5' || CHR(44) || 'R6' || CHR(44) ||
             'R7' || CHR(44) || 'R8' || CHR(44) || 'R9'
             AS col_header
      FROM DUAL;

    ---------------------------------------------------------------------------
    -- Cursor: Data rows for the CSV
    ---------------------------------------------------------------------------
    CURSOR csv_data_cur(p_request_id NUMBER) IS
      SELECT NVL(DEBIT_ACCOUNT,    '')                            || CHR(44) ||
             NVL(DEBIT_CURRENCY,   '')                            || CHR(44) ||
             NVL(TO_CHAR(VALUE_DATE, 'DD/MM/YYYY'), '')           || CHR(44) ||
             NVL(CREDIT_ACCOUNT,   '')                            || CHR(44) ||
             NVL(TO_CHAR(TRANSFER_AMOUNT), '')                    || CHR(44) ||
             NVL(BULKCUSTREFID,    '')                            || CHR(44) ||
             NVL(CHARGETYPE,       '')                            || CHR(44) ||
             NVL(TRANSFERPURPOSE,  '')                            || CHR(44) ||
             NVL(BENBANKSWIFTBICCODE, '')                         || CHR(44) ||
             NVL(BRANCHCODE,       '')                            || CHR(44) ||
             NVL(BANKCODE,         '')                            || CHR(44) ||
             NVL(BENEFICIARYNAME,  '')                            || CHR(44) ||
             NVL(BENEFICIARYREFERENCE, '')                        || CHR(44) ||
             NVL(BULKREFERENCE,    '')                            || CHR(44) ||
             NVL(FTCUSTREFID,      '')                            || CHR(44) ||
             NVL(CBO,              '')                            || CHR(44) ||
             NVL(PAYMENTDETAILS,   '')                            || CHR(44) ||
             NVL(PAYMENTCURRENCY,  '')                            || CHR(44) ||
             NVL(BENBRANCHNAME,    '')                            || CHR(44) ||
             NVL(BENBANKNAME,      '')                            || CHR(44) ||
             NVL(BENADDRESSLINE1,  '')                            || CHR(44) ||
             NVL(BENADDRESSLINE2,  '')                            || CHR(44) ||
             NVL(BENADDRESSLINE3,  '')                            || CHR(44) ||
             NVL(BENBANKADDRESSLINE3, '')                         || CHR(44) ||
             NVL(BENBANKCOUNTRY,   '')                            || CHR(44) ||
             NVL(NOTIFYBEN,        '')                            || CHR(44) ||
             NVL(NOTIFYBENEMAIL,   '')                            || CHR(44) ||
             NVL(NOTIFYBENCHOICE,  '')                            || CHR(44) ||
             NVL(BENBRANCHADDRESS1,'')                            || CHR(44) ||
             NVL(BENBRANCHADDRESS2,'')                            || CHR(44) ||
             NVL(BENBRANCHADDRESSCITY3, '')                       || CHR(44) ||
             NVL(SERVICECODE,      '')                            || CHR(44) ||
             NVL(TO_CHAR(SERVICEFX), '')                         || CHR(44) ||
             NVL(RATECODE,         '')                            || CHR(44) ||
             NVL(TO_CHAR(NUMBEROFRECORDS), '')                   || CHR(44) ||
             NVL(BATCHHEADERID,    '')                            || CHR(44) ||
             NVL(R1,'') || CHR(44) || NVL(R2,'') || CHR(44) || NVL(R3,'') || CHR(44) ||
             NVL(R4,'') || CHR(44) || NVL(R5,'') || CHR(44) || NVL(R6,'') || CHR(44) ||
             NVL(R7,'') || CHR(44) || NVL(R8,'') || CHR(44) || NVL(R9,'')
             AS line_section,
             CHECKRUN_NAME
      FROM   XXOA_PAYMENT_OU_SIB_STG
      WHERE  CHECKRUN_ID  = P_BATCH
      AND    REQUEST_ID   = p_request_id
      AND    NVL(TO_CHAR(RETCODE), '0') <> '1';

    ---------------------------------------------------------------------------
    -- Cursor: Records awaiting validation
    ---------------------------------------------------------------------------
    CURSOR rec_payment_data_cur(p_request_id NUMBER) IS
      SELECT *
      FROM   XXOA_PAYMENT_OU_SIB_STG
      WHERE  REQUEST_ID         = p_request_id
      AND    FILE_NAME         IS NULL
      AND    VALIDATION_STATUS IS NULL
      AND    VALIDATION_REMARKS IS NULL;

    -- Local variables
    l_validation_status  VARCHAR2(1)    := 'S';
    l_err_msg            VARCHAR2(4000);
    l_record_count       NUMBER         := 0;
    l_parent_request_id  NUMBER;
    l_request_id         NUMBER;
    l_stg_record_count   NUMBER;
    l_file               UTL_FILE.file_type;
    l_file_name          VARCHAR2(300);
    l_file_path          VARCHAR2(200);
    l_file_count         NUMBER         := 0;
    l_valid              VARCHAR2(10)   := 'N';
    l_batch_count        NUMBER         := 0;
    l_seq_no             NUMBER         := 0;
    l_retcode            NUMBER         := 0;
    l_flag               NUMBER         := 0;
    v_step               NUMBER         := 0;
    l_shr_file_path      VARCHAR2(200);
    l_user_id            NUMBER         := FND_PROFILE.VALUE('USER_ID');
    l_resp_id            NUMBER         := 50209;        -- TODO: Update with correct responsibility ID for Sohar
    l_resp_appl_id       NUMBER         := 200;
    l_bank_account_name  VARCHAR2(100);
    l_bank_name          VARCHAR2(360);
    -- File name parts (TODO: Replace placeholders with actual Bank Sohar values)
    lc_cust_ref          VARCHAR2(50)   := 'CUSTREF';    -- TODO: Replace with actual Customer Reference
    lc_entity_ref        VARCHAR2(50)   := 'ENTITYREF';  -- TODO: Replace with actual Entity Reference
    lc_appl_ref          VARCHAR2(50)   := 'APPREF';     -- TODO: Replace with actual Applicant Reference
    lc_accounting_type   VARCHAR2(10)   := 'MDMC';       -- TODO: Business to confirm MDMC or SDMC
    lc_processing_type   VARCHAR2(10)   := 'NSTP';       -- TODO: Business to confirm STP or NSTP

  BEGIN
    BEGIN
      fnd_file.put_line(fnd_file.LOG, '==========================================================');
      fnd_file.put_line(fnd_file.LOG, '   XXOA_AP_SIB_PAYMT_OUTB - Bank Sohar Payment Interface  ');
      fnd_file.put_line(fnd_file.LOG, '==========================================================');
      fnd_file.put_line(fnd_file.LOG, 'Inserting Records to Staging Table - START');

      l_parent_request_id := fnd_global.conc_request_id;

      fnd_file.put_line(fnd_file.LOG, 'P_BATCH              : ' || P_BATCH);
      fnd_file.put_line(fnd_file.LOG, 'l_parent_request_id  : ' || l_parent_request_id);

      -- Step 1: Insert AP payment data into staging
      Insert_pymt_datatostg(P_BATCH, l_stg_record_count, l_parent_request_id);
      COMMIT;

      fnd_file.put_line(fnd_file.LOG, 'Records Inserted into Staging : ' || l_stg_record_count);
      fnd_file.put_line(fnd_file.LOG, '----------------------------------------------------------');
      fnd_file.put_line(fnd_file.LOG, 'Outbound Validation - START');

      -- Step 2: Validation loop
      BEGIN
        FOR r1 IN rec_payment_data_cur(l_parent_request_id)
        LOOP
          l_flag              := 1;
          l_validation_status := 'S';
          l_err_msg           := NULL;
          l_batch_count       := 0;
          l_retcode           := 0;

          -----------------------------------------------------------------------
          -- Validation 1: Duplicate Batch Check
          -- Ensure the same CHECKRUN_NAME has not already been successfully processed
          -----------------------------------------------------------------------
          BEGIN
            SELECT COUNT(*)
            INTO   l_batch_count
            FROM   XXOA_PAYMENT_OU_SIB_STG
            WHERE  CHECKRUN_NAME   = r1.CHECKRUN_NAME
            AND    VALIDATION_STATUS = 'S'
            AND    REQUEST_ID     <> l_parent_request_id;
          EXCEPTION
            WHEN OTHERS THEN
              fnd_file.put_line(fnd_file.LOG, 'Error in Duplicate Batch Check: ' || SQLERRM);
          END;

          IF l_batch_count > 0 THEN
            l_validation_status := 'F';
            l_err_msg           := l_err_msg || CHR(10) || 'Payment Batch Already Exists: ' || r1.CHECKRUN_NAME || CHR(59);
            fnd_file.put_line(fnd_file.LOG, 'FAILED - Duplicate Batch: ' || r1.CHECKRUN_NAME);
            RETCODE   := 1;
            l_retcode := 1;
          END IF;

          -----------------------------------------------------------------------
          -- Validation 2: Mandatory Fields
          -----------------------------------------------------------------------
          IF   r1.DEBIT_ACCOUNT       IS NULL
            OR r1.DEBIT_CURRENCY      IS NULL
            OR r1.VALUE_DATE          IS NULL
            OR r1.CREDIT_ACCOUNT      IS NULL
            OR r1.TRANSFER_AMOUNT     IS NULL
            OR r1.BENEFICIARYNAME     IS NULL
            OR r1.PAYMENTCURRENCY     IS NULL
          THEN
            l_validation_status := 'F';
            RETCODE             := 1;
            l_retcode           := 1;
            l_err_msg           := l_err_msg || CHR(10) || 'Mandatory Fields cannot be null' || CHR(59);

            IF r1.DEBIT_ACCOUNT   IS NULL THEN
              l_err_msg := l_err_msg || CHR(10) || 'DEBIT_ACCOUNT is NULL' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - DEBIT_ACCOUNT IS NULL: ' || r1.CHECKRUN_NAME);
            END IF;
            IF r1.DEBIT_CURRENCY  IS NULL THEN
              l_err_msg := l_err_msg || CHR(10) || 'DEBIT_CURRENCY is NULL' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - DEBIT_CURRENCY IS NULL: ' || r1.CHECKRUN_NAME);
            END IF;
            IF r1.VALUE_DATE      IS NULL THEN
              l_err_msg := l_err_msg || CHR(10) || 'VALUE_DATE is NULL' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - VALUE_DATE IS NULL: ' || r1.CHECKRUN_NAME);
            END IF;
            IF r1.CREDIT_ACCOUNT  IS NULL THEN
              l_err_msg := l_err_msg || CHR(10) || 'CREDIT_ACCOUNT is NULL' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - CREDIT_ACCOUNT IS NULL: ' || r1.CHECKRUN_NAME);
            END IF;
            IF r1.TRANSFER_AMOUNT IS NULL THEN
              l_err_msg := l_err_msg || CHR(10) || 'TRANSFER_AMOUNT is NULL' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - TRANSFER_AMOUNT IS NULL: ' || r1.CHECKRUN_NAME);
            END IF;
            IF r1.BENEFICIARYNAME IS NULL THEN
              l_err_msg := l_err_msg || CHR(10) || 'BENEFICIARYNAME is NULL' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - BENEFICIARYNAME IS NULL: ' || r1.CHECKRUN_NAME);
            END IF;
            IF r1.PAYMENTCURRENCY IS NULL THEN
              l_err_msg := l_err_msg || CHR(10) || 'PAYMENTCURRENCY is NULL' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - PAYMENTCURRENCY IS NULL: ' || r1.CHECKRUN_NAME);
            END IF;
          END IF;

          -----------------------------------------------------------------------
          -- Validation 3: Value Date
          -- Must not be in the past; must not be more than 5 days ahead
          -----------------------------------------------------------------------
          IF r1.VALUE_DATE IS NOT NULL THEN
            IF TRUNC(r1.VALUE_DATE) < TRUNC(SYSDATE) THEN
              l_validation_status := 'F';
              RETCODE             := 1;
              l_retcode           := 1;
              l_err_msg           := l_err_msg || CHR(10) || 'VALUE_DATE cannot be in the past' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - VALUE_DATE is in the past: ' || r1.CHECKRUN_NAME);
            ELSIF TRUNC(r1.VALUE_DATE) > TRUNC(SYSDATE) + 5 THEN
              l_validation_status := 'F';
              RETCODE             := 1;
              l_retcode           := 1;
              l_err_msg           := l_err_msg || CHR(10) || 'VALUE_DATE cannot be more than 5 days from today' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - VALUE_DATE exceeds 5-day limit: ' || r1.CHECKRUN_NAME);
            END IF;
          END IF;

          -----------------------------------------------------------------------
          -- Validation 4: SWIFT Code mandatory for Foreign (non-OM) payments
          -- MT103 (foreign currency transfer) requires BenBankSwiftBICCode
          -----------------------------------------------------------------------
          IF NVL(r1.BENBANKCOUNTRY, 'XX') <> 'OM' THEN
            IF r1.BENBANKSWIFTBICCODE IS NULL THEN
              l_validation_status := 'F';
              RETCODE             := 1;
              l_retcode           := 1;
              l_err_msg           := l_err_msg || CHR(10) || 'BENBANKSWIFTBICCODE is mandatory for foreign transfers' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - BENBANKSWIFTBICCODE IS NULL for foreign payment: ' || r1.CHECKRUN_NAME);
            END IF;
          END IF;

          -----------------------------------------------------------------------
          -- Validation 5: TransferPurpose mandatory for UAE, CHINA, INDIA
          -----------------------------------------------------------------------
          IF r1.BENBANKCOUNTRY IN ('AE', 'CN', 'IN') THEN
            IF r1.TRANSFERPURPOSE IS NULL THEN
              l_validation_status := 'F';
              RETCODE             := 1;
              l_retcode           := 1;
              l_err_msg           := l_err_msg || CHR(10) || 'TRANSFERPURPOSE is mandatory for UAE, China, India payments' || CHR(59);
              fnd_file.put_line(fnd_file.LOG, 'FAILED - TRANSFERPURPOSE IS NULL for ' || r1.BENBANKCOUNTRY || ': ' || r1.CHECKRUN_NAME);
            END IF;
          END IF;

          -----------------------------------------------------------------------
          -- Update staging with validation result
          -----------------------------------------------------------------------
          IF l_validation_status = 'F' THEN
            UPDATE XXOA_PAYMENT_OU_SIB_STG
            SET    VALIDATION_STATUS  = 'F',
                   VALIDATION_REMARKS = l_err_msg,
                   RETCODE            = l_retcode
            WHERE  CHECKRUN_ID        = r1.CHECKRUN_ID
            AND    REQUEST_ID         = r1.REQUEST_ID
            AND    VALIDATION_STATUS IS NULL;
          ELSE
            UPDATE XXOA_PAYMENT_OU_SIB_STG
            SET    VALIDATION_STATUS  = 'S',
                   VALIDATION_REMARKS = NULL,
                   RETCODE            = 0
            WHERE  CHECKRUN_ID        = P_BATCH
            AND    REQUEST_ID         = l_parent_request_id
            AND    RETCODE           IS NULL
            AND    VALIDATION_STATUS IS NULL;
            COMMIT;
          END IF;

        END LOOP; -- end validation loop

        IF l_flag = 0 THEN
          fnd_file.put_line(fnd_file.LOG, 'WARNING: No records found in staging to validate.');
        END IF;

      END; -- end validation block

      fnd_file.put_line(fnd_file.LOG, 'Outbound Validation - END');
      fnd_file.put_line(fnd_file.LOG, '----------------------------------------------------------');

      -- Step 3: CSV File Generation
      fnd_file.put_line(fnd_file.LOG, 'CSV File Generation - START');

      BEGIN
        l_seq_no := 0;

        FOR payment_batch IN rec_payment_batch_cur
        LOOP
          fnd_file.put_line(fnd_file.LOG, 'Processing batch: ' || payment_batch.CHECKRUN_NAME);

          BEGIN
            -- Check if there are any failed records for this batch/request
            SELECT COUNT(CHECKRUN_NAME)
            INTO   l_record_count
            FROM   XXOA_PAYMENT_OU_SIB_STG
            WHERE  CHECKRUN_ID        = P_BATCH
            AND    REQUEST_ID         = l_parent_request_id
            AND    VALIDATION_STATUS  = 'F';

            IF l_record_count > 0 THEN
              l_valid := 'N';
            ELSE
              l_valid := 'Y';
            END IF;

            IF l_valid = 'Y' THEN

              -- Get the output directory path
              BEGIN
                SELECT directory_path
                INTO   l_file_path
                FROM   DBA_DIRECTORIES
                WHERE  directory_name = 'XXOA_SIB_REQ'; -- TODO: Confirm Oracle directory name for Sohar
              EXCEPTION
                WHEN NO_DATA_FOUND THEN
                  fnd_file.put_line(fnd_file.LOG, 'ERROR: Directory XXOA_SIB_REQ not found in DBA_DIRECTORIES');
                  l_file_path := NULL;
                WHEN OTHERS THEN
                  fnd_file.put_line(fnd_file.LOG, 'ERROR reading DBA_DIRECTORIES: ' || SQLERRM);
                  l_file_path := NULL;
              END;

              l_seq_no := l_seq_no + 1;

              ---------------------------------------------------------------------------
              -- Build file name per Bank Sohar format:
              -- <CustRef>_<EntityRef>_<ApplicantRef>_<AccountingType>_<ProcessingType>_BS_<DateTime>.csv
              ---------------------------------------------------------------------------
              l_file_name := lc_cust_ref
                          || '_' || lc_entity_ref
                          || '_' || lc_appl_ref
                          || '_' || lc_accounting_type
                          || '_' || lc_processing_type
                          || '_BS_'
                          || TO_CHAR(SYSDATE, 'DDMMYYHH24MISS')
                          || l_seq_no
                          || '.csv';

              fnd_file.put_line(fnd_file.LOG, 'File Name: ' || l_file_name);

              -- Open the file
              BEGIN
                l_file := UTL_FILE.fopen('XXOA_SIB_REQ', l_file_name, 'W');
                fnd_file.put_line(fnd_file.LOG, 'File opened successfully.');
              EXCEPTION
                WHEN OTHERS THEN
                  fnd_file.put_line(fnd_file.LOG, 'ERROR opening file: ' || SQLERRM);
              END;

              -- Write column header row
              FOR col_hdr IN csv_col_header_cur
              LOOP
                UTL_FILE.put(l_file, col_hdr.col_header);
                UTL_FILE.put(l_file, CHR(10));
              END LOOP;

              -- Write data rows
              FOR csv_data IN csv_data_cur(l_parent_request_id)
              LOOP
                UTL_FILE.put(l_file, csv_data.line_section);
                UTL_FILE.put(l_file, CHR(10));

                -- Update staging with file name
                UPDATE XXOA_PAYMENT_OU_SIB_STG
                SET    FILE_NAME  = l_file_name
                WHERE  CHECKRUN_NAME = csv_data.CHECKRUN_NAME
                AND    REQUEST_ID    = l_parent_request_id;

                -- Update AP_CHECKS_ALL with e-banking confirmation attributes
                UPDATE ap.ap_checks_all aca
                SET    aca.attribute_category = 'SIB EBanking_Confirmation',
                       aca.attribute1         = 'SIB-TRF',
                       aca.attribute7         = TO_CHAR(TRUNC(SYSDATE), 'DD-MON-YYYY'),
                       aca.last_update_login  = fnd_global.login_id,
                       aca.last_update_date   = SYSDATE,
                       aca.last_updated_by    = fnd_global.user_id
                WHERE  DECODE(SUBSTR(TRIM(aca.checkrun_name), 1, 5), 'Quick', aca.check_id, aca.checkrun_id) = P_BATCH;

                COMMIT;
              END LOOP;

              -- Close the file
              UTL_FILE.fclose(l_file);
              fnd_file.put_line(fnd_file.LOG, 'File created successfully: ' || l_file_name || ' at path: ' || l_file_path);

            ELSE
              -- Validation failed — mark records and skip file creation
              RETCODE := 1;
              l_valid := 'N';
              UPDATE XXOA_PAYMENT_OU_SIB_STG
              SET    VALIDATION_STATUS = 'F',
                     RETCODE           = 1
              WHERE  CHECKRUN_ID       = P_BATCH
              AND    REQUEST_ID        = l_parent_request_id;

              fnd_file.put_line(fnd_file.LOG, 'SKIPPED file creation - validation failures exist for batch: ' || payment_batch.CHECKRUN_NAME);
            END IF;

            fnd_file.put_line(fnd_file.LOG, '----------------------------------------------------------');

          EXCEPTION
            WHEN OTHERS THEN
              fnd_file.put_line(fnd_file.LOG, 'ERROR in file creation block: ' || SQLCODE || ' :: ' || SUBSTR(SQLERRM, 1, 200));
          END;

        END LOOP; -- end payment_batch loop

        fnd_file.put_line(fnd_file.LOG, 'CSV File Generation - END');
        COMMIT;

        -- Step 4: Send failure email notification
        payment_Vali_failure_det_email(l_parent_request_id);

        -- Step 5: Archive and purge error records
        error_records_archive_ins(l_parent_request_id);

        -- Step 6: Submit SFTP concurrent request if file(s) created
        SELECT COUNT(*)
        INTO   l_file_count
        FROM   XXOA_PAYMENT_OU_SIB_STG
        WHERE  REQUEST_ID = l_parent_request_id
        AND    FILE_NAME IS NOT NULL;

        fnd_file.put_line(fnd_file.LOG, 'L_VALID: ' || l_valid || '  l_file_count: ' || l_file_count);

        IF l_file_count > 0 AND l_valid = 'Y' THEN
          BEGIN
            fnd_global.apps_initialize(l_user_id, l_resp_id, l_resp_appl_id);
            -- TODO: Update properties file path for Bank Sohar once confirmed
            l_shr_file_path := '/EBSapps/appl/ap/12.0.0/bin/XXOA_AP_SIB_BANK_SFTP.properties';
            l_request_id    := fnd_request.submit_request(
                                   application => 'XXOA',
                                   program     => 'XXOA_AP_SIB_BANK_SFTP',  -- TODO: Confirm SFTP concurrent program name
                                   description => NULL,
                                   start_time  => NULL,
                                   sub_request => FALSE,
                                   argument1   => l_shr_file_path
                               );
            IF l_request_id = 0 THEN
              fnd_file.put_line(fnd_file.LOG, 'ERROR: SFTP Concurrent Request submission failed.');
            ELSE
              fnd_file.put_line(fnd_file.LOG, 'SFTP Concurrent Request submitted successfully. Request ID: ' || l_request_id);
            END IF;
          EXCEPTION
            WHEN OTHERS THEN
              fnd_file.put_line(fnd_file.LOG, 'ERROR submitting SFTP Concurrent Request: ' || SQLCODE || ' - ' || SQLERRM);
          END;
          COMMIT;
        END IF;

        -- Step 7: Log bank account details
        BEGIN
          SELECT DISTINCT cba.bank_account_name,
                          hp.party_name
          INTO   l_bank_account_name,
                 l_bank_name
          FROM   ap_checks_all ac,
                 ce_bank_acct_uses_all cbu,
                 ce_bank_accounts cba,
                 hz_parties hp
          WHERE  ac.ce_bank_acct_use_id  = cbu.bank_acct_use_id
          AND    cbu.bank_account_id     = cba.bank_account_id
          AND    cba.bank_id             = hp.party_id
          AND    DECODE(SUBSTR(TRIM(ac.checkrun_name), 1, 5), 'Quick', ac.check_id, ac.checkrun_id) = P_BATCH;

          fnd_file.put_line(fnd_file.LOG, 'Bank Account Name : ' || l_bank_account_name);
          fnd_file.put_line(fnd_file.LOG, 'Bank Name         : ' || l_bank_name);
        EXCEPTION
          WHEN OTHERS THEN
            fnd_file.put_line(fnd_file.LOG, 'WARNING: Could not fetch bank account details: ' || SQLERRM);
        END;

      EXCEPTION
        WHEN OTHERS THEN
          fnd_file.put_line(fnd_file.LOG, 'ERROR in CSV generation block: ' || SQLCODE || ' :: ' || SUBSTR(SQLERRM, 1, 200));
      END;

    END;

  EXCEPTION
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.LOG, '');
      fnd_file.put_line(fnd_file.LOG, 'MAIN EXCEPTION: ' || SQLCODE || ' at step ' || v_step || ' :: ' || SUBSTR(SQLERRM, 1, 200));
  END outbound_validation;


  ----------------------------------------------------------------------------
  -- PROCEDURE: Insert_pymt_datatostg
  -- Extracts AP payment data from EBS tables and inserts into SIB staging.
  ----------------------------------------------------------------------------
  PROCEDURE Insert_pymt_datatostg(
      P_BATCH        IN  NUMBER,
      P_record_count OUT NUMBER,
      P_request_id   IN  NUMBER
  )
  IS
    l_check_count    NUMBER := 0;
    l_count          NUMBER := 0;
    l_country_count  NUMBER := 0;
    l_batch          NUMBER;
    l_request_id     NUMBER;

    ---------------------------------------------------------------------------
    -- Main extraction cursor
    -- Maps AP/IBY tables to SIB staging columns
    -- Field mapping follows the Bank Sohar Payment File Format (45 fields)
    ---------------------------------------------------------------------------
    CURSOR cur_insert(p_batch NUMBER, p_request_id NUMBER) IS
      SELECT
        -- Field 1: DebitAccount - company bank account number
        ba.BANK_ACCOUNT_NUM                                                               AS debit_account,
        -- Field 2: DebitCurrency - currency of the debit bank account
        ba.CURRENCY_CODE                                                                  AS debit_currency,
        -- Field 3: ValueDate - payment check date in DD/MM/YYYY
        ch.check_date                                                                     AS value_date,
        -- Field 4: CreditAccount - beneficiary account (IBAN if available, else account number)
        CASE
          WHEN suppl_bank.BeneficiaryAccountCountry = 'OM'
          THEN TO_CHAR(suppl_bank.BeneficiaryAccountNumber)
          ELSE NVL(suppl_bank.iban_code, TO_CHAR(suppl_bank.BeneficiaryAccountNumber))
        END                                                                               AS credit_account,
        -- Field 5: TransferAmount
        ch.AMOUNT                                                                         AS transfer_amount,
        -- Field 6: BulkCustRefId (optional - blank per spec)
        NULL                                                                              AS bulkcustrefid,
        -- Field 7: ChargeType - OUR (business to confirm)
        'OUR'                                                                             AS chargetype,
        -- Field 8: TransferPurpose - mandatory for UAE/China/India (populated if available)
        NULL                                                                              AS transferpurpose, -- TODO: Map from payment batch DFF if maintained
        -- Field 9: BenBankSwiftBICCode
        SUBSTR(suppl_bank.BeneficiaryBankBICCode, 1, 11)                                 AS benbankswiftbiccode,
        -- Field 10: BranchCode (optional - blank)
        NULL                                                                              AS branchcode,
        -- Field 11: BankCode (optional - blank)
        NULL                                                                              AS bankcode,
        -- Field 12: BeneficiaryName - vendor name, special chars removed, max 35
        SUBSTR(REGEXP_REPLACE(suppl_bank.BeneficiaryName, '[^0-9A-Za-z ]', ' '), 1, 35) AS beneficiaryname,
        -- Field 13: BeneficiaryReference (optional - blank)
        NULL                                                                              AS beneficiaryreference,
        -- Field 14: BulkReference (optional - blank)
        NULL                                                                              AS bulkreference,
        -- Field 15: FTCustRefId - payment voucher/check number for reconciliation
        -- TODO: Business to confirm. Using CHECK_NUMBER as payment voucher reference.
        ch.CHECK_NUMBER                                                                   AS ftcustrefid,
        -- Field 16: CBO / Main Transfer of Purpose
        -- TODO: Discuss with business team and bank to confirm CBO purpose code mapping
        NULL                                                                              AS cbo,
        -- Field 17: PaymentDetails - invoice numbers (TODO: Business to confirm separator and source)
        NULL                                                                              AS paymentdetails,
        -- Field 18: PaymentCurrency - invoice/payment currency
        ch.CURRENCY_CODE                                                                  AS paymentcurrency,
        -- Field 19: BenBranchName (optional - blank)
        NULL                                                                              AS benbranchname,
        -- Field 20: BenBankName (optional - blank)
        NULL                                                                              AS benbankname,
        -- Field 21: BenAddressLine1 - mandatory for certain countries
        SUBSTR(REGEXP_REPLACE(suppl_bank.BeneficiaryAddress,    '[^0-9A-Za-z ]', ' '), 1, 33) AS benaddressline1,
        -- Field 22: BenAddressLine2
        SUBSTR(REGEXP_REPLACE(suppl_bank.BeneficiaryAddressLine2, '[^0-9A-Za-z ]', ' '), 1, 33) AS benaddressline2,
        -- Field 23: BenAddressLine3 (city)
        SUBSTR(REGEXP_REPLACE(suppl_bank.BeneficiaryCity,        '[^0-9A-Za-z ]', ' '), 1, 30) AS benaddressline3,
        -- Field 24: BenBankAddressLine1 (optional - blank)
        NULL                                                                              AS benbankaddressline3,
        -- Field 25: BenBankCountry - ISO 3166 2-char country code
        suppl_bank.BeneficiaryAccountCountry                                             AS benbankcountry,
        -- Field 26: NotifyBen (optional - blank)
        NULL                                                                              AS notifyben,
        -- Field 27: NotifyBenEmail (optional - blank)
        NULL                                                                              AS notifybenemail,
        -- Field 28: NotifyBenChoice (optional - blank)
        NULL                                                                              AS notifybenchoice,
        -- Field 29-31: BenBranchAddress (optional - blank)
        NULL                                                                              AS benbranchaddress1,
        NULL                                                                              AS benbranchaddress2,
        NULL                                                                              AS benbranchaddresscity3,
        -- Field 32: ServiceCode - IFSC for INR, Sort Code for GBP
        CASE
          WHEN ch.CURRENCY_CODE = 'INR' THEN suppl_bank.BeneficiaryIFSCCode
          WHEN ch.CURRENCY_CODE = 'GBP' THEN suppl_bank.BeneficiarySortCode
          ELSE NULL
        END                                                                               AS servicecode,
        -- Field 33: ServiceFX - special FX rate from treasury (optional - TODO: Business to confirm)
        NULL                                                                              AS servicefx,
        -- Field 34: RateCode - treasury rate code (optional - TODO: Business to confirm)
        NULL                                                                              AS ratecode,
        -- Field 35-44: Optional fields (blank per spec)
        NULL                                                                              AS numberofrecords,
        NULL                                                                              AS batchheaderid,
        NULL AS r1, NULL AS r2, NULL AS r3, NULL AS r4, NULL AS r5,
        NULL AS r6, NULL AS r7, NULL AS r8, NULL AS r9,
        -- Control columns
        NULL                                                                              AS file_name,
        DECODE(SUBSTR(TRIM(ch.checkrun_name), 1, 5), 'Quick', ch.check_id, ch.checkrun_id) AS checkrun_id,
        ch.checkrun_name                                                                  AS checkrun_name,
        br.bank_name                                                                      AS bank_name,
        br.BANK_HOME_COUNTRY                                                              AS bank_country,
        NULL                                                                              AS validation_status,
        NULL                                                                              AS validation_remarks,
        p_request_id                                                                      AS request_id,
        NULL                                                                              AS record_count,
        NULL                                                                              AS retcode,
        suppl_bank.ext_bank_account_id                                                   AS ext_bank_account_id,
        suppl_bank.BeneficiaryBankBICCode                                                AS swift_check
      FROM
        ap_checks_all              ch,
        ce_bank_accounts           ba,
        ce_bank_acct_uses_all      cbau,
        ce_bank_branches_v         br,
        ap_invoice_payments_all    aipa,
        ap.ap_invoices_all         aia,
        ap.ap_inv_selection_criteria_all aisca,
        iby_payments_all           ipa,
        fnd_lookup_values          flv,
        -- Beneficiary / Supplier bank details subquery
        (
          SELECT
            aps.vendor_name                                    AS BeneficiaryName,
            ass.ADDRESS_LINE1                                  AS BeneficiaryAddress,
            ass.ADDRESS_LINE2                                  AS BeneficiaryAddressLine2,
            ass.ADDRESS_LINE3                                  AS BeneficiaryAddressLine3,
            ass.CITY                                           AS BeneficiaryCity,
            ass.STATE                                          AS BeneficiaryState,
            ass.ZIP                                            AS BeneficiaryZip,
            hcp.email_address                                  AS BeneficiaryEmail,
            ieb.bank_account_num                               AS BeneficiaryAccountNumber,
            ieb.bank_account_name                              AS BeneficiaryAccountName,
            ass.country                                        AS BeneficiaryAccountCountry,
            ieb.iban                                           AS iban_code,
            ieb.ext_bank_account_id,
            ieb.currency_code                                  AS BeneficiaryAccountCurrency,
            SUBSTR(ieb.attribute1, 1, 11)                      AS BeneficiaryBankBICCode,
            NVL(ieb.attribute3, ieb.attribute2)                AS BeneficiaryIFSCCode,  -- IFSC for INR
            ieb.attribute4                                     AS BeneficiarySortCode,   -- Sort code for GBP (TODO: Confirm attribute mapping)
            party_bank.party_name                              AS BeneficiaryBankName,
            branch_prof.organization_name                      AS BeneficiaryBranchName,
            iep.ext_payee_id,
            iep.payee_party_id
          FROM
            hz_parties                  party_supp,
            ap_suppliers                aps,
            hz_party_sites              site_supp,
            ap_supplier_sites_all       ass,
            iby_external_payees_all     iep,
            iby_pmt_instr_uses_all      ipi,
            iby_ext_bank_accounts       ieb,
            hz_parties                  party_bank,
            hz_parties                  party_branch,
            hz_organization_profiles    bank_prof,
            hz_organization_profiles    branch_prof,
            hz_contact_points           hcp
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
      WHERE ch.ce_bank_acct_use_id           = cbau.bank_acct_use_id
      AND   cbau.bank_account_id             = ba.bank_account_id
      AND   ba.bank_branch_id                = br.branch_party_id
      AND   ch.check_id                      = aipa.check_id
      AND   ch.checkrun_id                   = aisca.checkrun_id(+)
      AND   aia.invoice_id                   = aipa.invoice_id
      AND   ch.payment_id                    = ipa.payment_id
      AND   ipa.payments_complete_flag       = 'Y'
      AND   suppl_bank.payee_party_id(+)     = ipa.payee_party_id
      AND   suppl_bank.ext_bank_account_id(+)= ch.external_bank_account_id
      AND   suppl_bank.ext_payee_id(+)       = ipa.ext_payee_id
      AND   ch.attribute_category           IS NULL
      -- Bank Sohar lookup filter: only process payments from Sohar bank accounts
      AND   flv.lookup_type                  = 'XXOA_SIB_EBANKING_BANK_ACC'  -- TODO: Confirm lookup name
      AND   flv.enabled_flag                 = 'Y'
      AND   UPPER(flv.attribute_category)    = UPPER('EBanking Bank Accounts')
      AND   UPPER(br.bank_name)              = UPPER(flv.attribute1)
      AND   UPPER(ch.bank_account_name)      = UPPER(flv.attribute2)
      AND   flv.language                     = 'US'
      AND   ch.status_lookup_code            = 'NEGOTIABLE'
      AND   DECODE(SUBSTR(TRIM(ch.checkrun_name), 1, 5), 'Quick', ch.check_id, ch.checkrun_id) = p_batch
      AND   ch.org_id                        = cbau.org_id
      AND   ch.org_id                        = aipa.org_id
      AND   UPPER(br.bank_name)              LIKE '%SOHAR%';  -- Safety filter for Bank Sohar only

  BEGIN
    -- Count checks for this batch
    SELECT COUNT(1)
    INTO   l_check_count
    FROM   ap_checks_all ac
    WHERE  DECODE(SUBSTR(TRIM(ac.checkrun_name), 1, 5), 'Quick', ac.check_id, ac.checkrun_id) = P_BATCH;

    fnd_file.put_line(fnd_file.LOG, 'Check Count for Batch: ' || l_check_count);

    l_batch      := p_batch;
    l_request_id := P_request_id;

    -- Validate batch does not mix OM and non-OM country payments
    BEGIN
      SELECT COUNT(1)
      INTO   l_country_count
      FROM (
        SELECT DISTINCT CHECKRUN_NAME,
               DECODE(COUNTRY, 'OM', 'OM', 'FC') BEN_NATIONALITY
        FROM   AP_CHECKS_ALL
        WHERE  DECODE(SUBSTR(TRIM(checkrun_name), 1, 5), 'Quick', check_id, checkrun_id) = P_BATCH
      );
    EXCEPTION
      WHEN OTHERS THEN
        fnd_file.put_line(fnd_file.LOG, 'Error in country count check: ' || SQLERRM);
    END;

    fnd_file.put_line(fnd_file.LOG, 'Country Count in Batch: ' || l_country_count);

    IF l_country_count > 1 THEN
      fnd_file.put_line(fnd_file.LOG, 'WARNING: Payment batch contains both Oman and foreign country payments.');
    END IF;

    -- Insert records into staging
    FOR c1 IN cur_insert(l_batch, l_request_id)
    LOOP
      IF c1.ext_bank_account_id IS NULL THEN
        fnd_file.put_line(fnd_file.LOG, 'SKIPPED - External Bank Account ID is NULL for: ' || c1.CHECKRUN_NAME);
      ELSIF c1.swift_check IS NULL AND NVL(c1.benbankcountry, 'XX') <> 'OM' THEN
        fnd_file.put_line(fnd_file.LOG, 'SKIPPED - SWIFT Code is NULL for foreign vendor: '
                          || c1.BENEFICIARYNAME || ' | Batch: ' || c1.CHECKRUN_NAME);
      ELSE
        fnd_file.put_line(fnd_file.LOG, 'Inserting record for batch: ' || c1.CHECKRUN_NAME);

        INSERT INTO XXOA.XXOA_PAYMENT_OU_SIB_STG
        (
          DEBIT_ACCOUNT,
          DEBIT_CURRENCY,
          VALUE_DATE,
          CREDIT_ACCOUNT,
          TRANSFER_AMOUNT,
          BULKCUSTREFID,
          CHARGETYPE,
          TRANSFERPURPOSE,
          BENBANKSWIFTBICCODE,
          BRANCHCODE,
          BANKCODE,
          BENEFICIARYNAME,
          BENEFICIARYREFERENCE,
          BULKREFERENCE,
          FTCUSTREFID,
          CBO,
          PAYMENTDETAILS,
          PAYMENTCURRENCY,
          BENBRANCHNAME,
          BENBANKNAME,
          BENADDRESSLINE1,
          BENADDRESSLINE2,
          BENADDRESSLINE3,
          BENBANKADDRESSLINE3,
          BENBANKCOUNTRY,
          NOTIFYBEN,
          NOTIFYBENEMAIL,
          NOTIFYBENCHOICE,
          BENBRANCHADDRESS1,
          BENBRANCHADDRESS2,
          BENBRANCHADDRESSCITY3,
          SERVICECODE,
          SERVICEFX,
          RATECODE,
          NUMBEROFRECORDS,
          BATCHHEADERID,
          R1, R2, R3, R4, R5, R6, R7, R8, R9,
          FILE_NAME,
          CHECKRUN_ID,
          CHECKRUN_NAME,
          BANK_NAME,
          BANK_COUNTRY,
          VALIDATION_STATUS,
          VALIDATION_REMARKS,
          REQUEST_ID,
          RECORD_COUNT,
          RETCODE
        )
        VALUES
        (
          c1.debit_account,
          c1.debit_currency,
          c1.value_date,
          c1.credit_account,
          c1.transfer_amount,
          c1.bulkcustrefid,
          c1.chargetype,
          c1.transferpurpose,
          c1.benbankswiftbiccode,
          c1.branchcode,
          c1.bankcode,
          c1.beneficiaryname,
          c1.beneficiaryreference,
          c1.bulkreference,
          c1.ftcustrefid,
          c1.cbo,
          c1.paymentdetails,
          c1.paymentcurrency,
          c1.benbranchname,
          c1.benbankname,
          c1.benaddressline1,
          c1.benaddressline2,
          c1.benaddressline3,
          c1.benbankaddressline3,
          c1.benbankcountry,
          c1.notifyben,
          c1.notifybenemail,
          c1.notifybenchoice,
          c1.benbranchaddress1,
          c1.benbranchaddress2,
          c1.benbranchaddresscity3,
          c1.servicecode,
          c1.servicefx,
          c1.ratecode,
          c1.numberofrecords,
          c1.batchheaderid,
          c1.r1, c1.r2, c1.r3, c1.r4, c1.r5,
          c1.r6, c1.r7, c1.r8, c1.r9,
          c1.file_name,
          c1.checkrun_id,
          c1.checkrun_name,
          c1.bank_name,
          c1.bank_country,
          c1.validation_status,
          c1.validation_remarks,
          c1.request_id,
          c1.record_count,
          c1.retcode
        );

        l_count := l_count + 1;
      END IF;
    END LOOP;

    -- Rollback if inserted count does not match expected check count
    IF l_count <> l_check_count THEN
      fnd_file.put_line(fnd_file.LOG, 'WARNING: Inserted count (' || l_count || ') does not match check count (' || l_check_count || '). Rolling back.');
      ROLLBACK;
    ELSE
      COMMIT;
      fnd_file.put_line(fnd_file.LOG, 'Successfully inserted ' || l_count || ' records into XXOA_PAYMENT_OU_SIB_STG.');
    END IF;

    P_record_count := l_count;

  END Insert_pymt_datatostg;


  ----------------------------------------------------------------------------
  -- PROCEDURE: payment_Vali_failure_det_email
  -- Sends a validation failure report as a CSV email attachment
  -- to the configured email recipients.
  ----------------------------------------------------------------------------
  PROCEDURE payment_Vali_failure_det_email(
      p_request_id IN NUMBER
  )
  IS
    l_v_mailhost       VARCHAR2(200);
    l_v_mail_from      VARCHAR2(200)  := 'applprod@omanair.com';
    l_v_attach_name    VARCHAR2(200)  := 'SIB_Payment_Validation_Error_' || p_request_id || '_' || TO_CHAR(SYSDATE, 'DDMMYYYY') || '.csv';
    l_v_mail_subject   VARCHAR2(2000) := 'Bank Sohar Payment Validation Errors - ' || p_request_id || ' - ' || TO_CHAR(SYSDATE, 'DDMMYYYY');
    l_v_mail_body      VARCHAR2(4000) := 'Hi,' || CHR(10) || CHR(10)
                                       || 'Please find the attached file for error records generated during the Bank Sohar (SIB) Interface Run.'
                                       || CHR(10) || CHR(10) || 'Thanks,' || CHR(10) || 'Oman Air Team';
    l_v_mail_to        VARCHAR2(1000);
    l_v_mail_id        VARCHAR2(1000);
    l_v_boundary       VARCHAR2(50)   := '----=*#abc1234321cba#*=';
    l_pi_step          PLS_INTEGER    := 24573;
    l_attach_clob      CLOB           := NULL;
    l_mail_conn        utl_smtp.connection;
    l_n_loop_ctr       NUMBER         := 0;
    l_v_error_message  VARCHAR2(2000);
    l_e_exception      EXCEPTION;

    -- Recipient email list from lookup
    CURSOR l_to_email_cur IS
      SELECT LISTAGG(flv.description, ',') WITHIN GROUP (ORDER BY flv.description) AS email_id
      FROM   apps.fnd_lookup_values flv
      WHERE  flv.lookup_type  = 'XXOA_SIB_TO_EMAIL_ADDRESS'  -- TODO: Confirm lookup name
      AND    flv.enabled_flag = 'Y'
      AND    flv.language     = 'US';

    -- Failed records to include in email attachment
    CURSOR l_get_erred_rec_cur IS
      SELECT DISTINCT CHECKRUN_NAME,
                      VALIDATION_STATUS,
                      VALIDATION_REMARKS
      FROM   XXOA_PAYMENT_OU_SIB_STG
      WHERE  REQUEST_ID        = p_request_id
      AND    VALIDATION_STATUS = 'F'
      AND    VALIDATION_REMARKS IS NOT NULL;

    TYPE l_get_erred_rec_tab IS TABLE OF l_get_erred_rec_cur%ROWTYPE INDEX BY PLS_INTEGER;
    l_error_record_tab l_get_erred_rec_tab;

  BEGIN
    -- Get mail host from lookup
    BEGIN
      SELECT flv.description
      INTO   l_v_mailhost
      FROM   apps.fnd_lookup_values flv
      WHERE  flv.lookup_type  = 'XXOA_SIB_MAIL_HOST'  -- TODO: Confirm lookup name
      AND    flv.enabled_flag = 'Y'
      AND    flv.language     = 'US';
    EXCEPTION
      WHEN OTHERS THEN
        l_v_error_message := 'Could not retrieve mail host from XXOA_SIB_MAIL_HOST lookup: ' || SQLERRM;
        RAISE l_e_exception;
    END;

    IF l_v_mail_from IS NULL THEN
      l_v_error_message := 'FROM email address is not configured.';
      RAISE l_e_exception;
    END IF;

    IF l_v_mailhost IS NULL THEN
      l_v_error_message := 'Mail host is not configured in XXOA_SIB_MAIL_HOST lookup.';
      RAISE l_e_exception;
    END IF;

    -- Build CSV header for attachment
    BEGIN
      SELECT 'Batch Name , Validation Status , Validation Remarks'
      INTO   l_attach_clob
      FROM   DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        l_v_error_message := 'Error building attachment header: ' || SQLERRM;
        RAISE l_e_exception;
    END;

    -- Collect all error records
    l_n_loop_ctr := 0;
    FOR rec IN l_get_erred_rec_cur
    LOOP
      l_n_loop_ctr := l_n_loop_ctr + 1;
      l_error_record_tab(l_n_loop_ctr).checkrun_name      := rec.checkrun_name;
      l_error_record_tab(l_n_loop_ctr).validation_status  := rec.validation_status;
      l_error_record_tab(l_n_loop_ctr).validation_remarks := rec.validation_remarks;
    END LOOP;

    -- Only send email if there are error records
    IF l_n_loop_ctr <> 0 THEN
      l_mail_conn := utl_smtp.open_connection(l_v_mailhost, 25);
      utl_smtp.helo(l_mail_conn, l_v_mailhost);
      utl_smtp.mail(l_mail_conn, l_v_mail_from);

      FOR l_to_email_rec IN l_to_email_cur
      LOOP
        l_v_mail_id := l_to_email_rec.email_id;
        utl_smtp.rcpt(l_mail_conn, l_v_mail_id);
        l_v_mail_to := l_v_mail_to || l_v_mail_id || ',';
        fnd_file.put_line(fnd_file.LOG, 'Sending email to: ' || l_v_mail_id);
      END LOOP;

      utl_smtp.open_data(l_mail_conn);
      utl_smtp.write_data(l_mail_conn, 'Date: '    || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'To: '      || l_v_mail_to    || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'From: '    || l_v_mail_from  || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'Subject: ' || l_v_mail_subject || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'Reply-To: '|| l_v_mail_from  || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'MIME-Version: 1.0'           || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'Content-Type: multipart/mixed; boundary="' || l_v_boundary || '"' || utl_tcp.crlf || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, '--' || l_v_boundary          || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'Content-Type: text/plain; charset="iso-8859-1"' || utl_tcp.crlf || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, l_v_mail_body);
      utl_smtp.write_data(l_mail_conn, utl_tcp.crlf || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, '--' || l_v_boundary          || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'Content-Type: text/csv; name="' || l_v_attach_name || '"' || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, 'Content-Disposition: attachment; filename="' || l_v_attach_name || '"' || utl_tcp.crlf || utl_tcp.crlf);

      -- Write CSV header line
      FOR i IN 0..TRUNC((DBMS_LOB.getlength(l_attach_clob) - 1) / l_pi_step)
      LOOP
        utl_smtp.write_data(l_mail_conn, DBMS_LOB.substr(l_attach_clob, l_pi_step, i * l_pi_step + 1));
      END LOOP;

      -- Write each error record as a CSV line
      FOR i IN l_error_record_tab.FIRST..l_error_record_tab.LAST
      LOOP
        l_attach_clob := CHR(13) || CHR(10);
        FOR j IN 0..TRUNC((DBMS_LOB.getlength(l_attach_clob) - 1) / l_pi_step)
        LOOP
          utl_smtp.write_data(l_mail_conn, DBMS_LOB.substr(l_attach_clob, l_pi_step, j * l_pi_step + 1));
        END LOOP;

        l_attach_clob := REPLACE(l_error_record_tab(i).checkrun_name,      ',', '.') || ' , '
                      || REPLACE(l_error_record_tab(i).validation_status,  ',', '.') || ' , '
                      || REPLACE(l_error_record_tab(i).validation_remarks, ',', '.');

        FOR j IN 0..TRUNC((DBMS_LOB.getlength(l_attach_clob) - 1) / l_pi_step)
        LOOP
          utl_smtp.write_data(l_mail_conn, DBMS_LOB.substr(l_attach_clob, l_pi_step, j * l_pi_step + 1));
        END LOOP;
      END LOOP;

      utl_smtp.write_data(l_mail_conn, utl_tcp.crlf || utl_tcp.crlf);
      utl_smtp.write_data(l_mail_conn, '--' || l_v_boundary || '--' || utl_tcp.crlf);
      utl_smtp.close_data(l_mail_conn);
      utl_smtp.quit(l_mail_conn);

      fnd_file.put_line(fnd_file.LOG, 'Validation failure email sent successfully.');
    ELSE
      fnd_file.put_line(fnd_file.LOG, 'No validation failures found. Email not sent.');
    END IF;

  EXCEPTION
    WHEN l_e_exception THEN
      fnd_file.put_line(fnd_file.LOG, 'EMAIL EXCEPTION: ' || l_v_error_message);
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.LOG, 'ERROR sending email: ' || SUBSTR(SQLERRM, 1, 3000));
  END payment_Vali_failure_det_email;


  ----------------------------------------------------------------------------
  -- PROCEDURE: error_records_archive_ins
  -- Moves failed staging records to the archive table and removes from staging.
  ----------------------------------------------------------------------------
  PROCEDURE error_records_archive_ins(
      p_request_id IN NUMBER
  )
  IS
  BEGIN
    -- Archive failed records
    INSERT INTO XXOA_PAYMENT_OU_SIB_ARC
      SELECT * FROM XXOA_PAYMENT_OU_SIB_STG
      WHERE  VALIDATION_STATUS = 'F'
      AND    REQUEST_ID        = p_request_id;

    -- Remove failed records from staging
    DELETE FROM XXOA_PAYMENT_OU_SIB_STG
    WHERE  VALIDATION_STATUS = 'F'
    AND    REQUEST_ID        = p_request_id;

    COMMIT;
    fnd_file.put_line(fnd_file.LOG, 'Error records archived and removed from staging for request: ' || p_request_id);

  EXCEPTION
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.LOG, 'ERROR in error_records_archive_ins: ' || SQLERRM);
  END error_records_archive_ins;


  ----------------------------------------------------------------------------
  -- PROCEDURE: xxoa_sib_bank_ack_ins
  -- Placeholder for processing Bank Sohar inbound acknowledgement files.
  -- TODO: Implement acknowledgement processing once bank provides spec.
  ----------------------------------------------------------------------------
  PROCEDURE xxoa_sib_bank_ack_ins(
      p_file_path IN VARCHAR2,
      p_file_name IN VARCHAR2
  )
  IS
    l_file_path  VARCHAR2(240);
    l_error_flag VARCHAR2(10) := 'N';
  BEGIN
    -- Validate directory exists
    BEGIN
      SELECT directory_name
      INTO   l_file_path
      FROM   dba_directories
      WHERE  directory_path = p_file_path;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        fnd_file.put_line(fnd_file.LOG, 'ERROR: Directory not found for path: ' || p_file_path);
        l_error_flag := 'Y';
    END;

    IF l_error_flag = 'N' THEN
      fnd_file.put_line(fnd_file.LOG, 'Acknowledgement directory resolved: ' || l_file_path);
      fnd_file.put_line(fnd_file.LOG, 'Processing file: ' || p_file_name);
      -- TODO: Implement acknowledgement insert logic once Bank Sohar provides the ack file format
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      fnd_file.put_line(fnd_file.LOG, 'ERROR in xxoa_sib_bank_ack_ins: ' || SQLERRM);
  END xxoa_sib_bank_ack_ins;

END XXOA_AP_SIB_PAYMT_OUTB;
/
