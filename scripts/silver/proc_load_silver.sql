
/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
===============================================================================
Script Purpose:
    This stored procedure loads data into the 'bronze' schema from external CSV files. 
    It performs the following actions:
    - Truncates the bronze tables before loading data.
    - Uses the `BULK INSERT` command to load data from csv Files to bronze tables.

Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC bronze.load_bronze;
===============================================================================
*/


CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME; 
    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '------------------------------------------------';

-- Loading silver.crm_cust_info
 SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_cust_info';
		TRUNCATE TABLE silver.crm_cust_info;
		PRINT '>> Inserting Data Into: silver.crm_cust_info';
        TRUNCATE TABLE silver.crm_cust_info;
INSERT INTO silver.crm_cust_info (
			cst_id, 
			cst_key, 
			 cst_firstname,
			  cst_lastname,
			cst_marital_status, 
			cst_gndr,
			cst_create_date
		)
  SELECT
			cst_id,
			cst_key,
			TRIM(cst_firstname) AS cst_firstname,
			TRIM(cst_lastname) AS cst_lastname,
			CASE 
				WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
				WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
				ELSE 'n/a'
			END AS cst_marital_status, -- Normalize marital status values to readable format
			CASE 
				WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
				WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
				ELSE 'n/a'
			END AS cst_gndr, -- Normalize gender values to readable format
			cst_create_date
		FROM (
			SELECT
				*,
				ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
			FROM bronze.crm_cust_info
			WHERE cst_id IS NOT NULL
		) t
		WHERE flag_last = 1; -- Select the most recent record per customer
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- Loading silver.crm_prd_info
         SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_prd_info';
		TRUNCATE TABLE silver.crm_prd_info;
		PRINT '>> Inserting Data Into: silver.crm_prd_info';
        INSERT INTO silver.crm_prd_info(
    prd_id,
    cat_id, 
    prd_key,
    prd_nm,
    prd_cost,
    prd_line, 
    prd_start_dt,
    prd_end_dt
)
SELECT 
      prd_id,
      
      -- replacing, because in erp table, this is with _(underscore)
     replace( SUBSTRING(prd_key, 1, 5), '-', '_')as cat_id,
     -- len - is used for dynamic
     SUBSTRING(prd_key, 7, len(prd_key)) as prd_key,
      prd_nm,
      -- replacing NULL with 0 
       isnull(prd_cost, 0)as prd_cost,
       CASE UPPER(TRIM(prd_line))
                    WHEN 'M' THEN 'Mountain'
                    WHEN 'R' THEN 'Road'
                    WHEN 'S' THEN 'Other Sales'
                    WHEN 'T' THEN 'Touring'
				ELSE 'n/a'
			END AS prd_line, 
            --removes time 
     CAST(prd_start_dt as date) as prd_start_dt,
     CAST(LEAD(prd_start_dt) over (Partition by prd_key order by prd_start_dt)-1 as date) as prd_end_dt

  FROM bronze.crm_prd_info;
   SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- Loading crm_sales_details
 SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_sales_details';
		TRUNCATE TABLE silver.crm_sales_details;
        PRINT '>> Inserting Data Into: silver.crm_sales_details';
        Insert INTO silver.crm_sales_details(
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    sls_order_dt,
    sls_ship_dt,
    sls_due_dt,
    sls_sales,
    sls_quantity,
    sls_price
)

SELECT 
  sls_ord_num,
  sls_prd_key,
  sls_cust_id,

  -- dates assumed numeric YYYYMMDD; TRY_CONVERT handles bad values
  CASE WHEN sls_order_dt = 0 OR LEN(sls_order_dt) <> 8
       THEN NULL
       ELSE TRY_CONVERT(date, CONVERT(varchar(8), sls_order_dt), 112)
  END AS sls_order_dt,

  CASE WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) <> 8
       THEN NULL
       ELSE TRY_CONVERT(date, CONVERT(varchar(8), sls_ship_dt), 112)
  END AS sls_ship_dt,

  CASE WHEN sls_due_dt = 0 OR LEN(sls_due_dt) <> 8
       THEN NULL
       ELSE TRY_CONVERT(date, CONVERT(varchar(8), sls_due_dt), 112)
  END AS sls_due_dt,

  CASE 
    WHEN sls_sales IS NULL OR sls_sales <= 0 
         OR sls_sales <> sls_quantity * ABS(sls_price)
      THEN sls_quantity * ABS(sls_price)
    ELSE sls_sales
  END AS sls_sales,

  sls_quantity,   -- <- missing comma was here

  CASE 
    WHEN sls_price IS NULL OR sls_price <= 0
      THEN sls_sales / NULLIF(sls_quantity, 0)
    ELSE sls_price
  END AS sls_price

FROM bronze.crm_sales_details;
 SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

-- Loading erp_cust_az12
        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_cust_az12';
		TRUNCATE TABLE silver.erp_cust_az12;
		PRINT '>> Inserting Data Into: silver.erp_cust_az12';
        Insert into silver.erp_cust_az12(cid, bdate, gen)
SELECT
			CASE
				WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid)) -- Remove 'NAS' prefix if present
				ELSE cid
			END AS cid, 
			CASE
				WHEN bdate > GETDATE() THEN NULL
				ELSE bdate
			END AS bdate, -- Set future birthdates to NULL
			CASE
				WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
				WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
				ELSE 'n/a'
			END AS gen -- Normalize gender values and handle unknown cases
FROM bronze.erp_cust_az12;
 SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

		PRINT '------------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '------------------------------------------------';

          -- Loading erp_loc_a101
        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_loc_a101';
		TRUNCATE TABLE silver.erp_loc_a101;
		PRINT '>> Inserting Data Into: silver.erp_loc_a101';
        INSERT INTO silver.erp_loc_a101 (
    cid,
    cntry
)
SELECT
    REPLACE(cid, '-', '') AS cid,   -- clean cid
    CASE 
        WHEN cntry_clean = 'DE' THEN 'Germany'
        WHEN cntry_clean IN ('US', 'USA') THEN 'United States'
        WHEN cntry_clean = '' OR cntry_clean IS NULL THEN 'n/a'
        ELSE cntry_clean
    END AS cntry
FROM bronze.erp_loc_a101
CROSS APPLY (
    SELECT 
      LTRIM(RTRIM(
        REPLACE(
          REPLACE(
            REPLACE(cntry, CHAR(13), ''),  -- remove CR
          CHAR(10), ''),                   -- remove LF
        CHAR(160), ' ')                    -- remove NBSP
      ))
) AS cleaner(cntry_clean);   -- 👈 end the statement here
	    SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';
        -- Loading erp_px_cat_g1v2
		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';
		TRUNCATE TABLE silver.erp_px_cat_g1v2;
		PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
        INSERT INTO silver.erp_px_cat_g1v2 (
			id,
			cat,
			subcat,
			maintenance
		)
		SELECT
			id,
			cat,
			subcat,
			maintenance
		FROM bronze.erp_px_cat_g1v2;
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';
        	SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Silver Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='
		
	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END

