-- =====================================================================
-- US ELECTRICITY PROJECT  |  FINAL FILE (schema + load + analysis)
-- 50 states + DC, 2000-2025.   Database: us_energy
--
-- INPUT: only the five cleaned tables that the notebook already saves
--   (import each CSV into us_energy under the same name):
--     consumption_clean.csv          -> consumption_clean
--     gdp_clean.csv                  -> gdp_clean
--     population_long.csv            -> population_long
--     us_state_generation_clean.csv  -> us_state_generation_clean
--     us_state_emissions_clean.csv   -> us_state_emissions_clean
--   unified_dataset is NOT needed: everything is rebuilt from the schema.
--
-- PART A  schema + load + checks   (creates the tables, run once)
-- PART B  analytical views         (everything below reads ONLY the schema)
-- PART C  analysis queries         (C6-C9 = emissions decomposition, real prices,
--                                   sub-periods, sensitivity tests)
-- PART D  export views
--
-- EER diagram note: the yellow objects in MySQL Workbench are VIEWS (v_*).
-- They are saved queries, not tables, and have no relationships. When you
-- reverse-engineer the diagram, untick Views (and the staging tables) to see
-- only the star schema.
--
-- Units: sales = MWh, revenues = thousand USD, price = cents/kWh,
--        GDP = million USD, generation = TWh, emissions = MtCO2e,
--        carbon intensity = gCO2e/kWh = 1000 * MtCO2e / TWh
-- =====================================================================

CREATE DATABASE IF NOT EXISTS us_energy;
USE us_energy;

-- =====================================================================
-- PART A. SCHEMA  (fact constellation: 3 fact tables by topic, 4 dimensions)
--
--   SUPPLY   fact_generation   (state, year, source)  generation + emissions
--   DEMAND   fact_consumption  (state, year, sector)  revenues, sales, customers, price
--   CONTEXT  fact_economy      (state, year)          population + GDP
--
--   dim_state   one row per state
--   dim_year    one row per year (+ CPI-U to deflate prices)
--   dim_source  Coal, Gas, Nuclear, ...
--   dim_sector  Residential, Commercial, Industrial, Total
--
-- Dimensions describe things; facts hold the numbers. Every dimension has ONE
-- simple key and the facts carry it as a foreign key. Consumption mirrors
-- generation: (state, year, sector) just like (state, year, source).
-- The facts meet through the shared dimensions (state_code, year).
-- =====================================================================

SET FOREIGN_KEY_CHECKS = 0;   -- lets the rebuild drop old tables whatever links they had
DROP TABLE IF EXISTS fact_generation;
DROP TABLE IF EXISTS fact_consumption;
DROP TABLE IF EXISTS fact_economy;
DROP TABLE IF EXISTS fact_state_year;     -- leftovers from earlier versions
DROP TABLE IF EXISTS dim_emissions;
DROP TABLE IF EXISTS dim_economy;
DROP TABLE IF EXISTS dim_consumption;
DROP TABLE IF EXISTS dim_sector;
DROP TABLE IF EXISTS dim_source;
DROP TABLE IF EXISTS dim_cpi;
DROP TABLE IF EXISTS dim_year;
DROP TABLE IF EXISTS dim_state;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE dim_state (
  state_code CHAR(2)     NOT NULL,
  state_name VARCHAR(50) NOT NULL,
  PRIMARY KEY (state_code)
) ENGINE=InnoDB;

-- cpi_u = annual CPI-U (1982-84 = 100), used only to deflate prices (section C7).
CREATE TABLE dim_year (
  year  SMALLINT NOT NULL,
  cpi_u DOUBLE   NOT NULL,
  PRIMARY KEY (year)
) ENGINE=InnoDB;

CREATE TABLE dim_source (
  source_id    TINYINT     NOT NULL AUTO_INCREMENT,
  source_name  VARCHAR(30) NOT NULL,
  is_renewable BOOLEAN     NOT NULL DEFAULT 0,
  is_fossil    BOOLEAN     NOT NULL DEFAULT 0,
  PRIMARY KEY (source_id),
  UNIQUE KEY uq_source_name (source_name)
) ENGINE=InnoDB;

-- is_total = 1 marks the 'Total' row; never add it to the other three sectors.
CREATE TABLE dim_sector (
  sector_id   TINYINT     NOT NULL,
  sector_name VARCHAR(20) NOT NULL,
  is_total    BOOLEAN     NOT NULL DEFAULT 0,
  PRIMARY KEY (sector_id),
  UNIQUE KEY uq_sector_name (sector_name)
) ENGINE=InnoDB;

-- SUPPLY. Units: generation = TWh, emissions = MtCO2e, intensity = gCO2e/kWh
CREATE TABLE fact_generation (
  state_code CHAR(2)  NOT NULL,
  year       SMALLINT NOT NULL,
  source_id  TINYINT  NOT NULL,
  generation_twh                DOUBLE,
  generation_share_pct          DOUBLE,
  emissions_mtco2e              DOUBLE,
  emissions_share_pct           DOUBLE,
  emissions_intensity_gco2e_kwh DOUBLE,
  PRIMARY KEY (state_code, year, source_id),
  KEY idx_fg_year (year),
  KEY idx_fg_source (source_id),
  CONSTRAINT fk_fg_state  FOREIGN KEY (state_code) REFERENCES dim_state (state_code),
  CONSTRAINT fk_fg_year   FOREIGN KEY (year)       REFERENCES dim_year (year),
  CONSTRAINT fk_fg_source FOREIGN KEY (source_id)  REFERENCES dim_source (source_id)
) ENGINE=InnoDB;

-- DEMAND. Units: revenues = thousand USD, sales = MWh, price = cents/kWh
CREATE TABLE fact_consumption (
  state_code CHAR(2)  NOT NULL,
  year       SMALLINT NOT NULL,
  sector_id  TINYINT  NOT NULL,
  revenues_k      DOUBLE,
  sales_mwh       DOUBLE,
  customers       BIGINT,
  price_cents_kwh DOUBLE,
  PRIMARY KEY (state_code, year, sector_id),
  KEY idx_fc_year (year),
  KEY idx_fc_sector (sector_id),
  CONSTRAINT fk_fc_state  FOREIGN KEY (state_code) REFERENCES dim_state (state_code),
  CONSTRAINT fk_fc_year   FOREIGN KEY (year)       REFERENCES dim_year (year),
  CONSTRAINT fk_fc_sector FOREIGN KEY (sector_id)  REFERENCES dim_sector (sector_id)
) ENGINE=InnoDB;

-- CONTEXT. Units: GDP and its components = million USD
CREATE TABLE fact_economy (
  state_code CHAR(2)  NOT NULL,
  year       SMALLINT NOT NULL,
  population                   BIGINT,
  real_gdp_musd2017            DOUBLE,
  gdp_current_musd             DOUBLE,
  compensation_musd            DOUBLE,
  gross_operating_surplus_musd DOUBLE,
  topi_less_subsidies_musd     DOUBLE,
  PRIMARY KEY (state_code, year),
  KEY idx_fe_year (year),
  CONSTRAINT fk_fe_state FOREIGN KEY (state_code) REFERENCES dim_state (state_code),
  CONSTRAINT fk_fe_year  FOREIGN KEY (year)       REFERENCES dim_year (year)
) ENGINE=InnoDB;

-- A.-1 SCHEMA CHECK: every link of the star schema. Expected: exactly 8 rows
--      (3 for fact_generation, 3 for fact_consumption, 2 for fact_economy).
--      Fewer rows = a table was not created with its links; re-run from the top.
SELECT TABLE_NAME AS child_table, COLUMN_NAME AS child_column,
       REFERENCED_TABLE_NAME AS parent_table, REFERENCED_COLUMN_NAME AS parent_column
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'us_energy' AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME, COLUMN_NAME;

-- =====================================================================
-- PART A. LOAD   (aggregate rows 'US' and 'PR' are excluded everywhere)
-- =====================================================================

-- 1) dim_year (CPI-U annual average, BLS, 1982-84 = 100).
--    !! 2025 is an approximation: replace it with the official BLS annual average.
INSERT INTO dim_year (year, cpi_u) VALUES
 (2000,172.200),(2001,177.100),(2002,179.900),(2003,184.000),(2004,188.900),
 (2005,195.300),(2006,201.600),(2007,207.342),(2008,215.303),(2009,214.537),
 (2010,218.056),(2011,224.939),(2012,229.594),(2013,232.957),(2014,236.736),
 (2015,237.017),(2016,240.007),(2017,245.120),(2018,251.107),(2019,255.657),
 (2020,258.811),(2021,270.970),(2022,292.655),(2023,304.702),(2024,313.689),
 (2025,322.000);

-- 2) dim_state. States are taken from EVERY source, so a state missing from
--    one file never loses its rows in the others.
INSERT INTO dim_state (state_code, state_name)
SELECT k.state_code,
       COALESCE(MAX(g.state_name), MAX(p.state), k.state_code)
FROM (
    SELECT state_code FROM consumption_clean
    UNION SELECT state_code FROM gdp_clean
    UNION SELECT state_code FROM population_long
    UNION SELECT `State code` FROM us_state_generation_clean
) k
LEFT JOIN gdp_clean       g ON g.state_code = k.state_code
LEFT JOIN population_long p ON p.state_code = k.state_code
WHERE k.state_code NOT IN ('US', 'PR')
GROUP BY k.state_code;

-- 3) dim_source
INSERT INTO dim_source (source_name, is_renewable, is_fossil)
SELECT DISTINCT
       `Electricity source`,
       `Electricity source` IN ('Bioenergy', 'Hydro', 'Solar', 'Wind', 'Other renewables'),
       `Electricity source` IN ('Coal', 'Gas', 'Other fossil')
FROM us_state_generation_clean
WHERE `Electricity source` IS NOT NULL;

-- 4) dim_sector
INSERT INTO dim_sector (sector_id, sector_name, is_total) VALUES
 (1, 'Residential', 0), (2, 'Commercial', 0), (3, 'Industrial', 0), (4, 'Total', 1);

-- 5) fact_generation: generation + emissions (same grain, one row each).
--    LEFT JOIN on emissions: a generation row is never lost for lack of an
--    emissions record (its emission columns are simply NULL).
INSERT INTO fact_generation
SELECT g.`State code`, g.`Year`, s.source_id,
       g.`Generation (TWh)`, g.`Share of generation (%)`,
       e.`Emissions (MtCO2e)`, e.`Share of emissions (%)`, e.`Emissions intensity (gCO2e/kWh)`
FROM us_state_generation_clean g
JOIN dim_source s  ON s.source_name = g.`Electricity source`
JOIN dim_state  st ON st.state_code = g.`State code`
LEFT JOIN us_state_emissions_clean e
       ON e.`State code` = g.`State code`
      AND e.`Year` = g.`Year`
      AND e.`Electricity source` = g.`Electricity source`;

-- 6) fact_consumption: the wide file (res_/com_/ind_/total_) turned into
--    one row per sector. Zero industrial sales are treated as missing.
INSERT INTO fact_consumption (state_code, year, sector_id, revenues_k, sales_mwh, customers, price_cents_kwh)
SELECT c.state_code, c.year, 1, c.res_revenues, c.res_sales, c.res_customers, c.res_price
FROM consumption_clean c JOIN dim_state st ON st.state_code = c.state_code
UNION ALL
SELECT c.state_code, c.year, 2, c.com_revenues, c.com_sales, c.com_customers, c.com_price
FROM consumption_clean c JOIN dim_state st ON st.state_code = c.state_code
UNION ALL
SELECT c.state_code, c.year, 3, c.ind_revenues, NULLIF(c.ind_sales, 0), c.ind_customers, c.ind_price
FROM consumption_clean c JOIN dim_state st ON st.state_code = c.state_code
UNION ALL
SELECT c.state_code, c.year, 4, c.total_revenues, c.total_sales, c.total_customers, c.total_price
FROM consumption_clean c JOIN dim_state st ON st.state_code = c.state_code;

-- 7) fact_economy: population + GDP. A row exists for every state-year that
--    appears in either file; the other measures are NULL if absent.
INSERT INTO fact_economy
SELECT k.state_code, k.year, p.population,
       g.real_gdp_musd2017, g.gdp_current_musd, g.compensation_musd,
       g.gross_operating_surplus_musd, g.topi_less_subsidies_musd
FROM (
    SELECT state_code, year FROM gdp_clean
    UNION SELECT state_code, year FROM population_long
) k
JOIN dim_state st             ON st.state_code = k.state_code
JOIN dim_year  yr             ON yr.year = k.year          -- study period only (2000-2025)
LEFT JOIN population_long p   ON p.state_code = k.state_code AND p.year = k.year
LEFT JOIN gdp_clean       g   ON g.state_code = k.state_code AND g.year = k.year;

-- =====================================================================
-- PART A. LOAD CHECKS  (read the result: source rows = loaded rows)
-- =====================================================================

-- A.0 STAGING ROW COUNTS. Check these BEFORE anything else.
--     The notebook produces: generation 9586, emissions 9586, consumption 1352
--     (52 areas x 26 years incl. the US row). If a count is lower, the CSV import
--     into MySQL lost rows (the Workbench import wizard does this silently).
--     Re-import that file; no query below can recover rows that never arrived.
SELECT 'us_state_generation_clean' AS staging_table, COUNT(*) AS rows_found, 9586 AS rows_expected
FROM us_state_generation_clean
UNION ALL SELECT 'us_state_emissions_clean', COUNT(*), 9586 FROM us_state_emissions_clean
UNION ALL SELECT 'consumption_clean',        COUNT(*), 1352 FROM consumption_clean;

-- A.1 Source vs loaded rows. Differences must be explained by US / PR only.
--     Puerto Rico is excluded on purpose (63 generation rows, no consumption data):
--     9586 source rows - 63 PR rows = 9523 rows expected in fact_generation.
SELECT 'generation_clean -> fact_generation' AS step,
       (SELECT COUNT(*) FROM us_state_generation_clean WHERE `State code` NOT IN ('US','PR')) AS source_rows,
       (SELECT COUNT(*) FROM fact_generation) AS loaded_rows
UNION ALL SELECT 'emissions_clean -> fact_generation (emission columns)',
       (SELECT COUNT(*) FROM us_state_emissions_clean WHERE `State code` NOT IN ('US','PR')),
       (SELECT COUNT(emissions_mtco2e) FROM fact_generation)
UNION ALL SELECT 'consumption_clean x 4 sectors -> fact_consumption',
       (SELECT 4 * COUNT(*) FROM consumption_clean WHERE state_code NOT IN ('US','PR')),
       (SELECT COUNT(*) FROM fact_consumption)
UNION ALL SELECT 'population_long -> fact_economy (population)',
       (SELECT COUNT(*) FROM population_long WHERE state_code NOT IN ('US','PR') AND year BETWEEN 2000 AND 2025),
       (SELECT COUNT(population) FROM fact_economy)
UNION ALL SELECT 'gdp_clean -> fact_economy (gdp)',
       (SELECT COUNT(*) FROM gdp_clean WHERE state_code NOT IN ('US','PR') AND year BETWEEN 2000 AND 2025),
       (SELECT COUNT(real_gdp_musd2017) FROM fact_economy);

-- A.2 Dimension sizes. Expected: 51 states, 26 years, 9 sources, 4 sectors
SELECT (SELECT COUNT(*) FROM dim_state)  AS states,
       (SELECT COUNT(*) FROM dim_year)   AS years,
       (SELECT COUNT(*) FROM dim_source) AS sources,
       (SELECT COUNT(*) FROM dim_sector) AS sectors;

-- A.3 fact_economy size. Expected: 51 states x 26 years = 1326 rows
SELECT COUNT(*) AS state_year_rows,
       SUM(population IS NULL)        AS without_population,
       SUM(real_gdp_musd2017 IS NULL) AS without_gdp
FROM fact_economy;

-- A.4 Row-loss diagnostic. Expected: zero rows. Any row listed here was in the
--     staging table but did not reach fact_generation (PR is ignored).
SELECT g.`State code` AS state_code, COUNT(*) AS generation_rows_lost
FROM us_state_generation_clean g
LEFT JOIN dim_source s ON s.source_name = g.`Electricity source`
LEFT JOIN fact_generation f
       ON f.state_code = g.`State code` AND f.year = g.`Year` AND f.source_id = s.source_id
WHERE g.`State code` NOT IN ('US', 'PR') AND f.state_code IS NULL
GROUP BY g.`State code`
ORDER BY generation_rows_lost DESC;

-- A.5 Final reconciliation: rows loaded vs expected
SELECT (SELECT COUNT(*) FROM us_state_generation_clean WHERE `State code` NOT IN ('US','PR')) AS expected_generation_rows,
       (SELECT COUNT(*) FROM fact_generation)  AS fact_generation_rows,
       (SELECT 4 * COUNT(*) FROM consumption_clean WHERE state_code NOT IN ('US','PR')) AS expected_consumption_rows,
       (SELECT COUNT(*) FROM fact_consumption) AS fact_consumption_rows,
       (SELECT COUNT(*) FROM fact_economy)     AS fact_economy_rows;

-- =====================================================================
-- PART B. ANALYTICAL VIEWS  (read only the schema above)
-- =====================================================================

-- B.0 Consumption turned back into one wide row per state-year
--     (sectors become columns again: handy for ratios and prices).
DROP VIEW IF EXISTS v_consumption_wide;
CREATE VIEW v_consumption_wide AS
SELECT c.state_code, c.year,
       SUM(CASE WHEN sc.sector_name = 'Residential' THEN c.revenues_k END) AS res_revenues,
       SUM(CASE WHEN sc.sector_name = 'Residential' THEN c.sales_mwh  END) AS res_sales,
       SUM(CASE WHEN sc.sector_name = 'Commercial'  THEN c.revenues_k END) AS com_revenues,
       SUM(CASE WHEN sc.sector_name = 'Commercial'  THEN c.sales_mwh  END) AS com_sales,
       SUM(CASE WHEN sc.sector_name = 'Industrial'  THEN c.revenues_k END) AS ind_revenues,
       SUM(CASE WHEN sc.sector_name = 'Industrial'  THEN c.sales_mwh  END) AS ind_sales,
       SUM(CASE WHEN sc.is_total = 1 THEN c.revenues_k END)                AS total_revenues,
       SUM(CASE WHEN sc.is_total = 1 THEN c.sales_mwh  END)                AS total_sales
FROM fact_consumption c
JOIN dim_sector sc ON sc.sector_id = c.sector_id
GROUP BY c.state_code, c.year;

-- B.1 State classification: structural break in the consumption series.
--     1 = 2025 sales < 70% of 2009 sales (14 states), 0 = healthy (37).
DROP VIEW IF EXISTS v_state_break;
CREATE VIEW v_state_break AS
SELECT state_code,
       CASE
         WHEN MAX(CASE WHEN year = 2025 THEN total_sales END) IS NULL
           OR MAX(CASE WHEN year = 2009 THEN total_sales END) IS NULL THEN NULL
         WHEN MAX(CASE WHEN year = 2025 THEN total_sales END) /
              NULLIF(MAX(CASE WHEN year = 2009 THEN total_sales END), 0) < 0.70 THEN 1
         ELSE 0
       END AS affected_break
FROM v_consumption_wide
GROUP BY state_code;

-- B.2 Generation + emissions per state-year
DROP VIEW IF EXISTS v_gen_state_year;
CREATE VIEW v_gen_state_year AS
SELECT g.state_code, g.year,
       SUM(g.generation_twh)                                                  AS total_generation_twh,
       SUM(CASE WHEN s.is_renewable = 1 THEN g.generation_twh ELSE 0 END)     AS renewable_twh,
       SUM(CASE WHEN s.is_fossil    = 1 THEN g.generation_twh ELSE 0 END)     AS fossil_twh,
       SUM(CASE WHEN s.source_name = 'Coal' THEN g.generation_twh ELSE 0 END) AS coal_twh,
       SUM(g.emissions_mtco2e)                                                AS total_emissions_mtco2e
FROM fact_generation g
JOIN dim_source s ON s.source_id = g.source_id
GROUP BY g.state_code, g.year;

-- B.3 Main analytical dataset: one wide row per state-year (state x year grid)
DROP VIEW IF EXISTS v_master;
CREATE VIEW v_master AS
SELECT d.state_code, d.state_name, b.affected_break, y.year, e.population,
       e.real_gdp_musd2017, e.gdp_current_musd,
       e.real_gdp_musd2017 * 1e6 / NULLIF(e.population, 0)    AS real_gdp_per_capita_usd,
       w.res_revenues, w.res_sales, w.com_revenues, w.com_sales,
       w.ind_revenues, w.ind_sales, w.total_revenues, w.total_sales,
       w.total_sales / NULLIF(e.population, 0)                AS consumption_per_capita_mwh,
       100.0 * w.res_revenues   / NULLIF(w.res_sales, 0)      AS p_res,
       100.0 * w.com_revenues   / NULLIF(w.com_sales, 0)      AS p_com,
       100.0 * w.ind_revenues   / NULLIF(w.ind_sales, 0)      AS p_ind,
       100.0 * w.total_revenues / NULLIF(w.total_sales, 0)    AS p_tot,
       g.total_generation_twh, g.renewable_twh, g.fossil_twh, g.coal_twh,
       g.total_emissions_mtco2e,
       100.0 * g.renewable_twh / NULLIF(g.total_generation_twh, 0)           AS renewable_share_pct,
       1000.0 * g.total_emissions_mtco2e / NULLIF(g.total_generation_twh, 0) AS carbon_intensity_g_kwh,
       g.total_generation_twh - w.total_sales / 1e6                          AS net_generation_twh
FROM dim_state d
CROSS JOIN dim_year y
LEFT JOIN v_state_break      b ON b.state_code = d.state_code
LEFT JOIN fact_economy       e ON e.state_code = d.state_code AND e.year = y.year
LEFT JOIN v_consumption_wide w ON w.state_code = d.state_code AND w.year = y.year
LEFT JOIN v_gen_state_year   g ON g.state_code = d.state_code AND g.year = y.year;

-- B.4 National annual series (sums of states, never the US aggregate row)
DROP VIEW IF EXISTS v_national_year;
CREATE VIEW v_national_year AS
SELECT year,
       SUM(total_generation_twh)                                    AS generation_twh,
       SUM(renewable_twh)                                           AS renewable_twh,
       SUM(fossil_twh)                                              AS fossil_twh,
       SUM(total_emissions_mtco2e)                                  AS emissions_mtco2e,
       SUM(total_sales) / 1e6                                       AS consumption_twh_all,
       SUM(CASE WHEN affected_break = 0 THEN total_sales END) / 1e6 AS consumption_twh_healthy,
       SUM(CASE WHEN affected_break = 1 THEN total_sales END) / 1e6 AS consumption_twh_affected,
       SUM(population)                                              AS population
FROM v_master
GROUP BY year;

-- B.5 Consumption series by classification
DROP VIEW IF EXISTS v_cons_series;
CREATE VIEW v_cons_series AS
SELECT 'healthy_37' AS scope, year, consumption_twh_healthy  AS twh FROM v_national_year
UNION ALL
SELECT 'affected_14',         year, consumption_twh_affected        FROM v_national_year
UNION ALL
SELECT 'all_51',              year, consumption_twh_all             FROM v_national_year;

-- =====================================================================
-- PART C. ANALYSIS
-- Rule: consumption TRENDS use affected_break = 0 (37 healthy states).
-- =====================================================================

-- ---------------------------------------------------------------------
-- C1. DATA QUALITY
-- ---------------------------------------------------------------------

-- C1.1 Row counts of the model
SELECT 'dim_state' AS tbl, COUNT(*) AS n FROM dim_state
UNION ALL SELECT 'dim_year',         COUNT(*) FROM dim_year
UNION ALL SELECT 'dim_source',       COUNT(*) FROM dim_source
UNION ALL SELECT 'dim_sector',       COUNT(*) FROM dim_sector
UNION ALL SELECT 'fact_generation',  COUNT(*) FROM fact_generation
UNION ALL SELECT 'fact_consumption', COUNT(*) FROM fact_consumption
UNION ALL SELECT 'fact_economy',     COUNT(*) FROM fact_economy;

-- C1.2 Missing values in the key measures
SELECT COUNT(*)                            AS state_years,
       SUM(population IS NULL)             AS missing_population,
       SUM(real_gdp_musd2017 IS NULL)      AS missing_gdp,
       SUM(total_sales IS NULL)            AS missing_consumption,
       SUM(total_generation_twh IS NULL)   AS missing_generation,
       SUM(total_emissions_mtco2e IS NULL) AS missing_emissions
FROM v_master;

-- C1.3 Data availability by year
SELECT year, COUNT(*) AS states, SUM(total_generation_twh IS NOT NULL) AS with_generation
FROM v_master
GROUP BY year
ORDER BY year;

-- C1.4 Classification groups. Expected: 37 healthy, 14 affected
SELECT affected_break, COUNT(*) AS states
FROM v_state_break
GROUP BY affected_break;

-- C1.5 The affected states (2025 vs 2009)
SELECT m.state_code, m.state_name,
       ROUND(MAX(CASE WHEN m.year = 2009 THEN m.total_sales END) / 1e6, 2) AS twh_2009,
       ROUND(MAX(CASE WHEN m.year = 2025 THEN m.total_sales END) / 1e6, 2) AS twh_2025,
       ROUND(MAX(CASE WHEN m.year = 2025 THEN m.total_sales END) /
             NULLIF(MAX(CASE WHEN m.year = 2009 THEN m.total_sales END), 0), 3) AS ratio_2025_2009
FROM v_master m
WHERE m.affected_break = 1
GROUP BY m.state_code, m.state_name
ORDER BY ratio_2025_2009;

-- C1.6 Year-over-year consumption jumps above 40% (candidate anomalies)
SELECT year, state_code, ROUND(prev_twh, 2) AS prev_twh, ROUND(twh, 2) AS twh,
       ROUND(100 * (twh / prev_twh - 1), 1) AS yoy_pct
FROM (
    SELECT year, state_code, total_sales / 1e6 AS twh,
           LAG(total_sales) OVER (PARTITION BY state_code ORDER BY year) / 1e6 AS prev_twh
    FROM v_consumption_wide
) x
WHERE prev_twh > 0 AND ABS(twh / prev_twh - 1) > 0.40
ORDER BY year, state_code;

-- C1.7 Generation vs consumption consistency (national)
SELECT year,
       ROUND(generation_twh, 1)      AS generation_twh,
       ROUND(consumption_twh_all, 1) AS consumption_twh,
       ROUND(consumption_twh_all / NULLIF(generation_twh, 0), 3) AS consumption_to_generation
FROM v_national_year
WHERE generation_twh IS NOT NULL
ORDER BY year;

-- ---------------------------------------------------------------------
-- C2. GENERATION AND EMISSIONS
-- ---------------------------------------------------------------------

-- C2.1 National generation, emissions, renewable share, carbon intensity
SELECT year,
       ROUND(generation_twh, 1)   AS generation_twh,
       ROUND(emissions_mtco2e, 1) AS emissions_mtco2e,
       ROUND(100 * renewable_twh / NULLIF(generation_twh, 0), 2)     AS renewable_share_pct,
       ROUND(100 * fossil_twh    / NULLIF(generation_twh, 0), 2)     AS fossil_share_pct,
       ROUND(1000 * emissions_mtco2e / NULLIF(generation_twh, 0), 1) AS carbon_intensity_g_kwh
FROM v_national_year
WHERE generation_twh IS NOT NULL
ORDER BY year;

-- C2.2 Generation and emissions by source, with shares
SELECT g.year, s.source_name,
       ROUND(SUM(g.generation_twh), 2) AS generation_twh,
       ROUND(100 * SUM(g.generation_twh) /
             NULLIF(SUM(SUM(g.generation_twh)) OVER (PARTITION BY g.year), 0), 2) AS generation_share_pct,
       ROUND(SUM(g.emissions_mtco2e), 2) AS emissions_mtco2e,
       ROUND(100 * SUM(g.emissions_mtco2e) /
             NULLIF(SUM(SUM(g.emissions_mtco2e)) OVER (PARTITION BY g.year), 0), 2) AS emissions_share_pct
FROM fact_generation g
JOIN dim_source s ON s.source_id = g.source_id
GROUP BY g.year, s.source_name
ORDER BY g.year, generation_twh DESC;

-- C2.3 Change per source: first year of data vs 2025
SELECT s.source_name,
       ROUND(SUM(CASE WHEN g.year = b.y0 THEN g.generation_twh END), 1) AS twh_first_year,
       ROUND(SUM(CASE WHEN g.year = 2025 THEN g.generation_twh END), 1) AS twh_2025,
       ROUND(SUM(CASE WHEN g.year = 2025 THEN g.generation_twh END) -
             SUM(CASE WHEN g.year = b.y0 THEN g.generation_twh END), 1) AS change_twh,
       ROUND(100 * (SUM(CASE WHEN g.year = 2025 THEN g.generation_twh END) /
             NULLIF(SUM(CASE WHEN g.year = b.y0 THEN g.generation_twh END), 0) - 1), 1) AS change_pct
FROM fact_generation g
JOIN dim_source s ON s.source_id = g.source_id
CROSS JOIN (SELECT MIN(year) AS y0 FROM fact_generation) b
GROUP BY s.source_name
ORDER BY change_twh DESC;

-- C2.4 Top 10 states by generation, 2025
SELECT RANK() OVER (ORDER BY total_generation_twh DESC) AS rnk,
       state_code, state_name,
       ROUND(total_generation_twh, 2)   AS generation_twh,
       ROUND(renewable_share_pct, 1)    AS renewable_share_pct,
       ROUND(carbon_intensity_g_kwh, 0) AS carbon_intensity_g_kwh
FROM v_master
WHERE year = 2025 AND total_generation_twh IS NOT NULL
ORDER BY rnk
LIMIT 10;

-- C2.5 Top 10 states by renewable generation (TWh), 2025
SELECT RANK() OVER (ORDER BY renewable_twh DESC) AS rnk,
       state_code, state_name,
       ROUND(renewable_twh, 2)       AS renewable_twh,
       ROUND(renewable_share_pct, 1) AS renewable_share_pct
FROM v_master
WHERE year = 2025 AND renewable_twh IS NOT NULL
ORDER BY rnk
LIMIT 10;

-- C2.6 Top 10 states by renewable SHARE, 2025 (states above 5 TWh only)
SELECT RANK() OVER (ORDER BY renewable_share_pct DESC) AS rnk,
       state_code, state_name,
       ROUND(renewable_share_pct, 1)  AS renewable_share_pct,
       ROUND(total_generation_twh, 1) AS generation_twh
FROM v_master
WHERE year = 2025 AND total_generation_twh >= 5
ORDER BY rnk
LIMIT 10;

-- C2.7 Cleanest and dirtiest grids, 2025 (states above 5 TWh)
(SELECT 'dirtiest' AS grp, state_code, state_name,
        ROUND(carbon_intensity_g_kwh, 0) AS carbon_intensity_g_kwh
 FROM v_master
 WHERE year = 2025 AND total_generation_twh >= 5 AND carbon_intensity_g_kwh IS NOT NULL
 ORDER BY carbon_intensity_g_kwh DESC LIMIT 5)
UNION ALL
(SELECT 'cleanest', state_code, state_name, ROUND(carbon_intensity_g_kwh, 0)
 FROM v_master
 WHERE year = 2025 AND total_generation_twh >= 5 AND carbon_intensity_g_kwh IS NOT NULL
 ORDER BY carbon_intensity_g_kwh ASC LIMIT 5);

-- C2.8 Biggest cuts in carbon intensity (first year vs 2025)
SELECT m.state_code, m.state_name,
       ROUND(MAX(CASE WHEN m.year = b.y0 THEN m.carbon_intensity_g_kwh END), 0) AS intensity_first_year,
       ROUND(MAX(CASE WHEN m.year = 2025 THEN m.carbon_intensity_g_kwh END), 0) AS intensity_2025,
       ROUND(MAX(CASE WHEN m.year = 2025 THEN m.carbon_intensity_g_kwh END) -
             MAX(CASE WHEN m.year = b.y0 THEN m.carbon_intensity_g_kwh END), 0) AS change_g_kwh
FROM v_master m
CROSS JOIN (SELECT MIN(year) AS y0 FROM fact_generation) b
WHERE m.total_generation_twh >= 5
GROUP BY m.state_code, m.state_name
HAVING intensity_first_year IS NOT NULL AND intensity_2025 IS NOT NULL
ORDER BY change_g_kwh ASC
LIMIT 10;

-- C2.9 Biggest coal declines (TWh, first year vs 2025)
SELECT m.state_code, m.state_name,
       ROUND(MAX(CASE WHEN m.year = b.y0 THEN m.coal_twh END), 1) AS coal_twh_first_year,
       ROUND(MAX(CASE WHEN m.year = 2025 THEN m.coal_twh END), 1) AS coal_twh_2025,
       ROUND(MAX(CASE WHEN m.year = 2025 THEN m.coal_twh END) -
             MAX(CASE WHEN m.year = b.y0 THEN m.coal_twh END), 1) AS change_twh
FROM v_master m
CROSS JOIN (SELECT MIN(year) AS y0 FROM fact_generation) b
GROUP BY m.state_code, m.state_name
HAVING coal_twh_first_year IS NOT NULL AND coal_twh_2025 IS NOT NULL
ORDER BY change_twh ASC
LIMIT 10;

-- ---------------------------------------------------------------------
-- C3. CONSUMPTION
-- ---------------------------------------------------------------------

-- C3.1 National consumption by sector with shares
SELECT year,
       ROUND(SUM(res_sales)   / 1e6, 1) AS res_twh,
       ROUND(SUM(com_sales)   / 1e6, 1) AS com_twh,
       ROUND(SUM(ind_sales)   / 1e6, 1) AS ind_twh,
       ROUND(SUM(total_sales) / 1e6, 1) AS total_twh,
       ROUND(100 * SUM(res_sales) / NULLIF(SUM(total_sales), 0), 1) AS res_share_pct,
       ROUND(100 * SUM(com_sales) / NULLIF(SUM(total_sales), 0), 1) AS com_share_pct,
       ROUND(100 * SUM(ind_sales) / NULLIF(SUM(total_sales), 0), 1) AS ind_share_pct
FROM v_master
GROUP BY year
ORDER BY year;

-- C3.2 Healthy vs affected series with year-over-year change
SELECT year,
       ROUND(MAX(CASE WHEN scope = 'all_51'      THEN twh END), 1) AS twh_all,
       ROUND(MAX(CASE WHEN scope = 'healthy_37'  THEN twh END), 1) AS twh_healthy,
       ROUND(MAX(CASE WHEN scope = 'affected_14' THEN twh END), 1) AS twh_affected,
       ROUND(MAX(CASE WHEN scope = 'all_51'      THEN yoy END), 2) AS yoy_all_pct,
       ROUND(MAX(CASE WHEN scope = 'healthy_37'  THEN yoy END), 2) AS yoy_healthy_pct,
       ROUND(MAX(CASE WHEN scope = 'affected_14' THEN yoy END), 2) AS yoy_affected_pct
FROM (
    SELECT scope, year, twh,
           100 * (twh / LAG(twh) OVER (PARTITION BY scope ORDER BY year) - 1) AS yoy
    FROM v_cons_series
) z
GROUP BY year
ORDER BY year;

-- C3.3 Growth, CAGR and linear trend 2000-2025 per series
SELECT scope, n,
       ROUND(twh_2000, 1) AS twh_2000,
       ROUND(twh_2025, 1) AS twh_2025,
       ROUND(100 * (twh_2025 / twh_2000 - 1), 2)                AS growth_pct,
       ROUND(100 * (POW(twh_2025 / twh_2000, 1.0 / 25) - 1), 3) AS cagr_pct,
       ROUND(slope, 3)                                           AS slope_twh_per_year,
       ROUND(r * r, 4)                                           AS r2
FROM (
    SELECT scope, COUNT(*) AS n,
           MAX(CASE WHEN year = 2000 THEN twh END) AS twh_2000,
           MAX(CASE WHEN year = 2025 THEN twh END) AS twh_2025,
           (COUNT(*) * SUM(year * twh) - SUM(year) * SUM(twh)) /
           (COUNT(*) * SUM(year * year) - SUM(year) * SUM(year)) AS slope,
           (COUNT(*) * SUM(year * twh) - SUM(year) * SUM(twh)) /
           SQRT((COUNT(*) * SUM(year * year) - SUM(year) * SUM(year)) *
                (COUNT(*) * SUM(twh * twh)   - SUM(twh)  * SUM(twh))) AS r
    FROM v_cons_series
    GROUP BY scope
) t
ORDER BY scope;

-- C3.4 Top 10 consuming states, 2025
SELECT RANK() OVER (ORDER BY total_sales DESC) AS rnk,
       state_code, state_name,
       ROUND(total_sales / 1e6, 2) AS twh_2025,
       ROUND(100 * total_sales / SUM(total_sales) OVER (), 2) AS share_of_national_pct,
       CASE WHEN affected_break = 1 THEN '*** BREAK ***' ELSE '' END AS break_flag
FROM v_master
WHERE year = 2025 AND total_sales IS NOT NULL
ORDER BY rnk
LIMIT 10;

-- C3.5 Top 10 states by consumption growth 2000-2025 (healthy states)
SELECT RANK() OVER (ORDER BY growth_pct DESC) AS rnk,
       state_code, state_name,
       ROUND(twh_2000, 2) AS twh_2000, ROUND(twh_2025, 2) AS twh_2025,
       ROUND(growth_pct, 1) AS growth_pct, ROUND(cagr_pct, 2) AS cagr_pct
FROM (
    SELECT state_code, state_name,
           SUM(CASE WHEN year = 2000 THEN total_sales END) / 1e6 AS twh_2000,
           SUM(CASE WHEN year = 2025 THEN total_sales END) / 1e6 AS twh_2025,
           100 * (SUM(CASE WHEN year = 2025 THEN total_sales END) /
                  NULLIF(SUM(CASE WHEN year = 2000 THEN total_sales END), 0) - 1) AS growth_pct,
           100 * (POW(SUM(CASE WHEN year = 2025 THEN total_sales END) /
                  NULLIF(SUM(CASE WHEN year = 2000 THEN total_sales END), 0), 1.0 / 25) - 1) AS cagr_pct
    FROM v_master
    WHERE affected_break = 0
    GROUP BY state_code, state_name
) g
WHERE growth_pct IS NOT NULL
ORDER BY rnk
LIMIT 10;

-- C3.6 Highest and lowest consumption per capita, 2025 (healthy states, MWh/person)
(SELECT 'highest' AS grp, state_code, state_name, ROUND(consumption_per_capita_mwh, 2) AS mwh_per_capita
 FROM v_master
 WHERE year = 2025 AND affected_break = 0 AND state_code <> 'DC'
 ORDER BY consumption_per_capita_mwh DESC LIMIT 5)
UNION ALL
(SELECT 'lowest', state_code, state_name, ROUND(consumption_per_capita_mwh, 2)
 FROM v_master
 WHERE year = 2025 AND affected_break = 0 AND state_code <> 'DC'
 ORDER BY consumption_per_capita_mwh ASC LIMIT 5);

-- C3.7 Top 10 states by population growth 2000-2025
SELECT state_code, state_name,
       MAX(CASE WHEN year = 2000 THEN population END) AS pop_2000,
       MAX(CASE WHEN year = 2025 THEN population END) AS pop_2025,
       ROUND(100 * (MAX(CASE WHEN year = 2025 THEN population END) /
             NULLIF(MAX(CASE WHEN year = 2000 THEN population END), 0) - 1), 1) AS growth_pct
FROM v_master
GROUP BY state_code, state_name
HAVING pop_2000 IS NOT NULL AND pop_2025 IS NOT NULL
ORDER BY growth_pct DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- C4. PRICES  (cents/kWh, sales-weighted: revenue / sales)
-- ---------------------------------------------------------------------

-- C4.1 National weighted prices by sector
SELECT year,
       ROUND(100.0 * SUM(res_revenues)   / SUM(res_sales),   2) AS res_price,
       ROUND(100.0 * SUM(com_revenues)   / SUM(com_sales),   2) AS com_price,
       ROUND(100.0 * SUM(ind_revenues)   / SUM(ind_sales),   2) AS ind_price,
       ROUND(100.0 * SUM(total_revenues) / SUM(total_sales), 2) AS tot_price
FROM v_master
GROUP BY year
ORDER BY year;

-- C4.2 Price dispersion across states (coefficient of variation) per year
SELECT year,
       ROUND(STDDEV_SAMP(p_res) / AVG(p_res), 4) AS cv_res,
       ROUND(STDDEV_SAMP(p_com) / AVG(p_com), 4) AS cv_com,
       ROUND(STDDEV_SAMP(p_ind) / AVG(p_ind), 4) AS cv_ind,
       ROUND(STDDEV_SAMP(p_tot) / AVG(p_tot), 4) AS cv_tot
FROM v_master
GROUP BY year
ORDER BY year;

-- C4.3 Is dispersion rising or falling? (trend of each sector's CV)
SELECT sector, n,
       ROUND(cv_2000, 4) AS cv_2000,
       ROUND(cv_2025, 4) AS cv_2025,
       ROUND(slope, 5)   AS slope_cv_per_year,
       CASE WHEN slope > 0 THEN 'dispersion INCREASING' ELSE 'dispersion DECREASING' END AS verdict
FROM (
    SELECT sector, COUNT(*) AS n,
           (COUNT(*) * SUM(year * cv) - SUM(year) * SUM(cv)) /
           (COUNT(*) * SUM(year * year) - SUM(year) * SUM(year)) AS slope,
           MAX(CASE WHEN year = 2000 THEN cv END) AS cv_2000,
           MAX(CASE WHEN year = 2025 THEN cv END) AS cv_2025
    FROM (
        SELECT 'residential' AS sector, year, STDDEV_SAMP(p_res) / AVG(p_res) AS cv FROM v_master GROUP BY year
        UNION ALL
        SELECT 'commercial',  year, STDDEV_SAMP(p_com) / AVG(p_com) FROM v_master GROUP BY year
        UNION ALL
        SELECT 'industrial',  year, STDDEV_SAMP(p_ind) / AVG(p_ind) FROM v_master GROUP BY year
        UNION ALL
        SELECT 'total',       year, STDDEV_SAMP(p_tot) / AVG(p_tot) FROM v_master GROUP BY year
    ) cvs
    GROUP BY sector
) s
ORDER BY sector;

-- C4.4 Most and least expensive residential electricity, 2025
(SELECT 'most expensive' AS grp, state_code, state_name, ROUND(p_res, 2) AS res_price
 FROM v_master WHERE year = 2025 AND p_res IS NOT NULL ORDER BY p_res DESC LIMIT 5)
UNION ALL
(SELECT 'cheapest', state_code, state_name, ROUND(p_res, 2)
 FROM v_master WHERE year = 2025 AND p_res IS NOT NULL ORDER BY p_res ASC LIMIT 5);

-- C4.5 Residential price vs consumption per capita: correlation per year
--      (healthy states, DC excluded)
SELECT year, n,
       ROUND((n * sxy - sx * sy) /
             NULLIF(SQRT((n * sxx - sx * sx) * (n * syy - sy * sy)), 0), 4) AS pearson_r
FROM (
    SELECT year, COUNT(*) AS n,
           SUM(p_res) AS sx, SUM(consumption_per_capita_mwh) AS sy,
           SUM(p_res * consumption_per_capita_mwh) AS sxy,
           SUM(p_res * p_res) AS sxx,
           SUM(consumption_per_capita_mwh * consumption_per_capita_mwh) AS syy
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC'
      AND p_res IS NOT NULL AND consumption_per_capita_mwh IS NOT NULL
    GROUP BY year
) a
ORDER BY year;

-- ---------------------------------------------------------------------
-- C5. ECONOMY AND ENERGY
-- ---------------------------------------------------------------------

-- C5.1 Electricity intensity of the economy (kWh per real GDP dollar), healthy states
SELECT year,
       ROUND(1000 * SUM(total_sales) / NULLIF(SUM(real_gdp_musd2017) * 1e6, 0), 6) AS kwh_per_real_gdp_usd
FROM v_master
WHERE affected_break = 0 AND state_code <> 'DC' AND real_gdp_musd2017 > 0
GROUP BY year
ORDER BY year;

-- C5.2 Trend of that intensity (slope per year)
SELECT COUNT(*) AS n,
       ROUND((COUNT(*) * SUM(year * i) - SUM(year) * SUM(i)) /
             NULLIF(COUNT(*) * SUM(year * year) - SUM(year) * SUM(year), 0), 9) AS intensity_slope_per_year
FROM (
    SELECT year, 1000 * SUM(total_sales) / NULLIF(SUM(real_gdp_musd2017) * 1e6, 0) AS i
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC' AND real_gdp_musd2017 > 0
    GROUP BY year
) t;

-- C5.3 Real GDP per capita vs electricity per capita (all healthy state-years):
--      Pearson r, R2, regression line and Spearman rho in one query
WITH pts AS (
    SELECT consumption_per_capita_mwh AS x, real_gdp_per_capita_usd AS y
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC'
      AND consumption_per_capita_mwh IS NOT NULL AND real_gdp_per_capita_usd IS NOT NULL
),
rk AS (
    SELECT x, y, RANK() OVER (ORDER BY x) AS rx, RANK() OVER (ORDER BY y) AS ry FROM pts
),
a AS (
    SELECT COUNT(*) AS n, SUM(x) AS sx, SUM(y) AS sy, SUM(x * y) AS sxy,
           SUM(x * x) AS sxx, SUM(y * y) AS syy,
           SUM(rx) AS srx, SUM(ry) AS sry, SUM(rx * ry) AS srxy,
           SUM(rx * rx) AS srxx, SUM(ry * ry) AS sryy
    FROM rk
)
SELECT n,
       ROUND((n * sxy - sx * sy) / NULLIF(SQRT((n * sxx - sx * sx) * (n * syy - sy * sy)), 0), 4) AS pearson_r,
       ROUND(POW((n * sxy - sx * sy) / NULLIF(SQRT((n * sxx - sx * sx) * (n * syy - sy * sy)), 0), 2), 4) AS r_squared,
       ROUND((n * sxy - sx * sy) / NULLIF(n * sxx - sx * sx, 0), 4) AS slope_usd_per_mwh,
       ROUND((n * srxy - srx * sry) / NULLIF(SQRT((n * srxx - srx * srx) * (n * sryy - sry * sry)), 0), 4) AS spearman_rho
FROM a;

-- C5.4 Same correlation, year by year (is the relationship stable?)
SELECT year, n,
       ROUND((n * sxy - sx * sy) /
             NULLIF(SQRT((n * sxx - sx * sx) * (n * syy - sy * sy)), 0), 4) AS pearson_r
FROM (
    SELECT year, COUNT(*) AS n,
           SUM(real_gdp_per_capita_usd) AS sx, SUM(consumption_per_capita_mwh) AS sy,
           SUM(real_gdp_per_capita_usd * consumption_per_capita_mwh) AS sxy,
           SUM(real_gdp_per_capita_usd * real_gdp_per_capita_usd) AS sxx,
           SUM(consumption_per_capita_mwh * consumption_per_capita_mwh) AS syy
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC'
      AND real_gdp_per_capita_usd IS NOT NULL AND consumption_per_capita_mwh IS NOT NULL
    GROUP BY year
) a
ORDER BY year;

-- C5.5 Decoupling: real GDP growth vs consumption growth 2000-2025 (healthy states)
SELECT state_code, state_name,
       ROUND(cons_growth_pct, 1) AS cons_growth_pct,
       ROUND(gdp_growth_pct, 1)  AS gdp_growth_pct,
       ROUND(gdp_growth_pct - cons_growth_pct, 1) AS gdp_minus_cons_pp,
       CASE WHEN cons_growth_pct <= 0 AND gdp_growth_pct > 0 THEN 'absolute decoupling'
            WHEN gdp_growth_pct > cons_growth_pct              THEN 'relative decoupling'
            ELSE 'coupled' END AS pattern
FROM (
    SELECT state_code, state_name,
           100 * (MAX(CASE WHEN year = 2025 THEN total_sales END) /
                  NULLIF(MAX(CASE WHEN year = 2000 THEN total_sales END), 0) - 1) AS cons_growth_pct,
           100 * (MAX(CASE WHEN year = 2025 THEN real_gdp_musd2017 END) /
                  NULLIF(MAX(CASE WHEN year = 2000 THEN real_gdp_musd2017 END), 0) - 1) AS gdp_growth_pct
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC'
    GROUP BY state_code, state_name
) g
WHERE cons_growth_pct IS NOT NULL AND gdp_growth_pct IS NOT NULL
ORDER BY gdp_minus_cons_pp DESC;

-- C5.6 Net exporters and importers of electricity, 2025 (generation minus sales)
SELECT state_code, state_name,
       ROUND(total_sales / 1e6, 2)    AS consumption_twh,
       ROUND(total_generation_twh, 2) AS generation_twh,
       ROUND(net_generation_twh, 2)   AS net_generation_twh,
       CASE WHEN net_generation_twh > 0 THEN 'net exporter' ELSE 'net importer' END AS position
FROM v_master
WHERE year = 2025 AND affected_break = 0
  AND total_sales IS NOT NULL AND total_generation_twh IS NOT NULL
ORDER BY net_generation_twh DESC;

-- C5.7 Did states that added more renewables cut carbon intensity more?
--      Pearson r between the change in renewable share and in carbon intensity
WITH y AS (SELECT MIN(year) AS y0 FROM fact_generation),
d AS (
    SELECT m.state_code,
           MAX(CASE WHEN m.year = 2025 THEN m.renewable_share_pct END) -
           MAX(CASE WHEN m.year = y.y0 THEN m.renewable_share_pct END) AS d_ren_pp,
           MAX(CASE WHEN m.year = 2025 THEN m.carbon_intensity_g_kwh END) -
           MAX(CASE WHEN m.year = y.y0 THEN m.carbon_intensity_g_kwh END) AS d_int
    FROM v_master m
    CROSS JOIN y
    WHERE m.total_generation_twh >= 5 AND m.state_code <> 'DC'
    GROUP BY m.state_code
),
a AS (
    SELECT COUNT(*) AS n, SUM(d_ren_pp) AS sx, SUM(d_int) AS sy,
           SUM(d_ren_pp * d_int) AS sxy, SUM(d_ren_pp * d_ren_pp) AS sxx, SUM(d_int * d_int) AS syy
    FROM d
    WHERE d_ren_pp IS NOT NULL AND d_int IS NOT NULL
)
SELECT n,
       ROUND((n * sxy - sx * sy) / NULLIF(SQRT((n * sxx - sx * sx) * (n * syy - sy * sy)), 0), 4) AS pearson_r
FROM a;

-- ---------------------------------------------------------------------
-- C6. WHY DID EMISSIONS CHANGE?  (decomposition)
-- Emissions = generation x carbon intensity. A fall in emissions can come
-- from less generation (scale), a cleaner mix, or cleaner plants.
-- ---------------------------------------------------------------------

-- C6.1 National LMDI decomposition by source for four periods.
--      change in emissions = activity + mix + emission-factor  (exact)
--        activity = effect of total generation growth
--        mix      = effect of shifting between sources
--        factor   = effect of each source emitting more/less per TWh
--      Only sources that emit in BOTH years are decomposed (coverage shown).
WITH periods AS (
    SELECT 2001 AS y0, 2007 AS y1 UNION ALL
    SELECT 2007, 2019            UNION ALL
    SELECT 2019, 2025            UNION ALL
    SELECT 2001, 2025
),
src AS (
    SELECT g.year, g.source_id,
           SUM(g.generation_twh)   AS gen,
           SUM(g.emissions_mtco2e) AS em
    FROM fact_generation g
    GROUP BY g.year, g.source_id
),
tot AS (SELECT year, SUM(gen) AS gen, SUM(em) AS em FROM src GROUP BY year),
pair AS (
    SELECT p.y0, p.y1, a.source_id,
           a.gen AS g0, b.gen AS g1, a.em AS e0, b.em AS e1,
           ta.gen AS tg0, tb.gen AS tg1
    FROM periods p
    JOIN src a  ON a.year = p.y0
    JOIN src b  ON b.year = p.y1 AND b.source_id = a.source_id
    JOIN tot ta ON ta.year = p.y0
    JOIN tot tb ON tb.year = p.y1
    WHERE a.em > 0 AND b.em > 0 AND a.gen > 0 AND b.gen > 0
),
lm AS (
    SELECT *, CASE WHEN e1 = e0 THEN e0 ELSE (e1 - e0) / LN(e1 / e0) END AS L
    FROM pair
)
SELECT lm.y0, lm.y1,
       ROUND(t0.em, 1) AS emissions_start,
       ROUND(t1.em, 1) AS emissions_end,
       ROUND(t1.em - t0.em, 1) AS total_change_mt,
       ROUND(SUM(L * LN(tg1 / tg0)), 1)                          AS activity_effect_mt,
       ROUND(SUM(L * LN((g1 / tg1) / (g0 / tg0))), 1)            AS mix_effect_mt,
       ROUND(SUM(L * LN((e1 / g1) / (e0 / g0))), 1)              AS factor_effect_mt,
       ROUND(SUM(e1 - e0), 1)                                    AS decomposed_change_mt
FROM lm
JOIN tot t0 ON t0.year = lm.y0
JOIN tot t1 ON t1.year = lm.y1
GROUP BY lm.y0, lm.y1, t0.em, t1.em
ORDER BY lm.y0, lm.y1;
-- Read it: total_change_mt vs decomposed_change_mt should be close; the three
-- effects add up to decomposed_change_mt exactly.

-- C6.2 State-level two-factor decomposition, first year vs 2025
--      (states above 5 TWh; Shapley midpoint, adds up exactly)
WITH y AS (SELECT MIN(year) AS y0 FROM fact_generation),
s AS (
    SELECT m.state_code, m.state_name,
           MAX(CASE WHEN m.year = y.y0 THEN m.total_generation_twh END) AS g0,
           MAX(CASE WHEN m.year = 2025 THEN m.total_generation_twh END) AS g1,
           MAX(CASE WHEN m.year = y.y0 THEN m.total_emissions_mtco2e END) AS e0,
           MAX(CASE WHEN m.year = 2025 THEN m.total_emissions_mtco2e END) AS e1
    FROM v_master m CROSS JOIN y
    WHERE m.total_generation_twh >= 5
    GROUP BY m.state_code, m.state_name
)
SELECT state_code, state_name,
       ROUND(e0, 1) AS emissions_first_year,
       ROUND(e1, 1) AS emissions_2025,
       ROUND(e1 - e0, 1) AS change_mt,
       ROUND((g1 - g0) * (e0 / g0 + e1 / g1) / 2, 1) AS activity_effect_mt,
       ROUND((e1 / g1 - e0 / g0) * (g0 + g1) / 2, 1) AS intensity_effect_mt
FROM s
WHERE e0 IS NOT NULL AND e1 IS NOT NULL AND g0 > 0 AND g1 > 0
ORDER BY change_mt ASC
LIMIT 15;

-- C6.3 Emissions per capita and per real GDP dollar, national (healthy-data years)
SELECT m.year,
       ROUND(SUM(m.total_emissions_mtco2e) * 1e6 / SUM(m.population), 3)            AS tco2e_per_person,
       ROUND(SUM(m.total_emissions_mtco2e) * 1e12 / SUM(m.real_gdp_musd2017 * 1e6), 2) AS gco2e_per_real_gdp_usd
FROM v_master m
WHERE m.total_emissions_mtco2e IS NOT NULL
GROUP BY m.year
ORDER BY m.year;

-- ---------------------------------------------------------------------
-- C7. REAL (INFLATION-ADJUSTED) PRICES, in 2025 dollars
-- ---------------------------------------------------------------------

-- C7.1 National prices by sector: nominal vs real
SELECT n.year,
       ROUND(n.res_price, 2) AS res_nominal,
       ROUND(n.res_price * ref.cpi_u / c.cpi_u, 2) AS res_real_2025usd,
       ROUND(n.com_price * ref.cpi_u / c.cpi_u, 2) AS com_real_2025usd,
       ROUND(n.ind_price * ref.cpi_u / c.cpi_u, 2) AS ind_real_2025usd,
       ROUND(n.tot_price * ref.cpi_u / c.cpi_u, 2) AS tot_real_2025usd
FROM (
    SELECT year,
           100.0 * SUM(res_revenues)   / SUM(res_sales)   AS res_price,
           100.0 * SUM(com_revenues)   / SUM(com_sales)   AS com_price,
           100.0 * SUM(ind_revenues)   / SUM(ind_sales)   AS ind_price,
           100.0 * SUM(total_revenues) / SUM(total_sales) AS tot_price
    FROM v_master
    GROUP BY year
) n
JOIN dim_year c   ON c.year = n.year
JOIN dim_year ref ON ref.year = 2025
ORDER BY n.year;

-- C7.2 Did electricity get more expensive in real terms? 2000 vs 2025
SELECT sector,
       ROUND(nom_2000, 2) AS nominal_2000,
       ROUND(nom_2025, 2) AS nominal_2025,
       ROUND(100 * (nom_2025 / nom_2000 - 1), 1) AS nominal_change_pct,
       ROUND(100 * (nom_2025 / nom_2000 * c0.cpi_u / c1.cpi_u - 1), 1) AS real_change_pct,
       ROUND(100 * (c1.cpi_u / c0.cpi_u - 1), 1) AS cpi_change_pct
FROM (
    SELECT 'residential' AS sector,
           100.0 * SUM(CASE WHEN year = 2000 THEN res_revenues END) / SUM(CASE WHEN year = 2000 THEN res_sales END) AS nom_2000,
           100.0 * SUM(CASE WHEN year = 2025 THEN res_revenues END) / SUM(CASE WHEN year = 2025 THEN res_sales END) AS nom_2025
    FROM v_master
    UNION ALL
    SELECT 'commercial',
           100.0 * SUM(CASE WHEN year = 2000 THEN com_revenues END) / SUM(CASE WHEN year = 2000 THEN com_sales END),
           100.0 * SUM(CASE WHEN year = 2025 THEN com_revenues END) / SUM(CASE WHEN year = 2025 THEN com_sales END)
    FROM v_master
    UNION ALL
    SELECT 'industrial',
           100.0 * SUM(CASE WHEN year = 2000 THEN ind_revenues END) / SUM(CASE WHEN year = 2000 THEN ind_sales END),
           100.0 * SUM(CASE WHEN year = 2025 THEN ind_revenues END) / SUM(CASE WHEN year = 2025 THEN ind_sales END)
    FROM v_master
    UNION ALL
    SELECT 'total',
           100.0 * SUM(CASE WHEN year = 2000 THEN total_revenues END) / SUM(CASE WHEN year = 2000 THEN total_sales END),
           100.0 * SUM(CASE WHEN year = 2025 THEN total_revenues END) / SUM(CASE WHEN year = 2025 THEN total_sales END)
    FROM v_master
) p
JOIN dim_year c0 ON c0.year = 2000
JOIN dim_year c1 ON c1.year = 2025;

-- C7.3 States where the real residential price rose or fell the most, 2000 -> 2025
SELECT m.state_code, m.state_name,
       ROUND(MAX(CASE WHEN m.year = 2000 THEN m.p_res * r.cpi_u / c.cpi_u END), 2) AS real_res_2000,
       ROUND(MAX(CASE WHEN m.year = 2025 THEN m.p_res END), 2)                     AS real_res_2025,
       ROUND(100 * (MAX(CASE WHEN m.year = 2025 THEN m.p_res END) /
             NULLIF(MAX(CASE WHEN m.year = 2000 THEN m.p_res * r.cpi_u / c.cpi_u END), 0) - 1), 1) AS real_change_pct
FROM v_master m
JOIN dim_year c ON c.year = m.year
JOIN dim_year r ON r.year = 2025
WHERE m.year IN (2000, 2025) AND m.p_res IS NOT NULL
GROUP BY m.state_code, m.state_name
HAVING real_res_2000 IS NOT NULL AND real_res_2025 IS NOT NULL
ORDER BY real_change_pct DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- C8. SUB-PERIODS  (a single 2000-2025 number hides the real story)
-- Periods: 2000-2007 growth | 2007-2019 plateau | 2019-2025 recent
-- ---------------------------------------------------------------------

-- C8.1 Consumption CAGR by period and sector (healthy 37 states)
WITH periods AS (
    SELECT '2000-2007' AS period, 2000 AS y0, 2007 AS y1 UNION ALL
    SELECT '2007-2019', 2007, 2019                         UNION ALL
    SELECT '2019-2025', 2019, 2025                         UNION ALL
    SELECT '2000-2025', 2000, 2025
),
y AS (
    SELECT year,
           SUM(res_sales) AS res, SUM(com_sales) AS com, SUM(ind_sales) AS ind,
           SUM(total_sales) AS tot, SUM(population) AS pop
    FROM v_master
    WHERE affected_break = 0
    GROUP BY year
)
SELECT p.period,
       ROUND(100 * (POW(b.res / a.res, 1.0 / (p.y1 - p.y0)) - 1), 2) AS res_cagr_pct,
       ROUND(100 * (POW(b.com / a.com, 1.0 / (p.y1 - p.y0)) - 1), 2) AS com_cagr_pct,
       ROUND(100 * (POW(b.ind / a.ind, 1.0 / (p.y1 - p.y0)) - 1), 2) AS ind_cagr_pct,
       ROUND(100 * (POW(b.tot / a.tot, 1.0 / (p.y1 - p.y0)) - 1), 2) AS total_cagr_pct,
       ROUND(100 * (POW(b.pop / a.pop, 1.0 / (p.y1 - p.y0)) - 1), 2) AS population_cagr_pct,
       ROUND(100 * (POW((b.tot / b.pop) / (a.tot / a.pop), 1.0 / (p.y1 - p.y0)) - 1), 2) AS per_capita_cagr_pct
FROM periods p
JOIN y a ON a.year = p.y0
JOIN y b ON b.year = p.y1
ORDER BY p.y0, p.y1;

-- C8.2 Generation, emissions, renewable share and real GDP by period (national)
WITH periods AS (
    SELECT '2001-2007' AS period, 2001 AS y0, 2007 AS y1 UNION ALL
    SELECT '2007-2019', 2007, 2019                         UNION ALL
    SELECT '2019-2025', 2019, 2025                         UNION ALL
    SELECT '2001-2025', 2001, 2025
),
gdp AS (
    SELECT year, SUM(real_gdp_musd2017) AS real_gdp
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC'
    GROUP BY year
)
SELECT p.period,
       ROUND(100 * (POW(b.generation_twh   / a.generation_twh,   1.0 / (p.y1 - p.y0)) - 1), 2) AS generation_cagr_pct,
       ROUND(100 * (POW(b.emissions_mtco2e / a.emissions_mtco2e, 1.0 / (p.y1 - p.y0)) - 1), 2) AS emissions_cagr_pct,
       ROUND(100 * b.renewable_twh / b.generation_twh - 100 * a.renewable_twh / a.generation_twh, 2) AS renewable_share_change_pp,
       ROUND(1000 * a.emissions_mtco2e / a.generation_twh, 1) AS intensity_start_g_kwh,
       ROUND(1000 * b.emissions_mtco2e / b.generation_twh, 1) AS intensity_end_g_kwh,
       ROUND(100 * (POW(gb.real_gdp / ga.real_gdp, 1.0 / (p.y1 - p.y0)) - 1), 2) AS real_gdp_cagr_pct
FROM periods p
JOIN v_national_year a ON a.year = p.y0
JOIN v_national_year b ON b.year = p.y1
JOIN gdp ga ON ga.year = p.y0
JOIN gdp gb ON gb.year = p.y1
ORDER BY p.y0, p.y1;

-- C8.3 Which states drove the 2019-2025 acceleration? (healthy states, TWh added)
SELECT state_code, state_name,
       ROUND(twh_2019, 2) AS twh_2019,
       ROUND(twh_2025, 2) AS twh_2025,
       ROUND(twh_2025 - twh_2019, 2) AS added_twh,
       ROUND(100 * (twh_2025 / twh_2019 - 1), 1) AS growth_pct
FROM (
    SELECT state_code, state_name,
           SUM(CASE WHEN year = 2019 THEN total_sales END) / 1e6 AS twh_2019,
           SUM(CASE WHEN year = 2025 THEN total_sales END) / 1e6 AS twh_2025
    FROM v_master
    WHERE affected_break = 0
    GROUP BY state_code, state_name
) t
WHERE twh_2019 > 0 AND twh_2025 IS NOT NULL
ORDER BY added_twh DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- C9. SENSITIVITY: do the conclusions survive different thresholds?
-- ---------------------------------------------------------------------

-- C9.1 Break threshold (2025 / 2009 ratio): how many states are excluded and
--      how much does the healthy-group CAGR 2000-2025 move?
WITH st AS (
    SELECT state_code,
           SUM(CASE WHEN year = 2000 THEN total_sales END) AS c00,
           SUM(CASE WHEN year = 2009 THEN total_sales END) AS c09,
           SUM(CASE WHEN year = 2025 THEN total_sales END) AS c25
    FROM v_master
    GROUP BY state_code
),
th AS (
    SELECT 0.60 AS t UNION ALL SELECT 0.65 UNION ALL SELECT 0.70
    UNION ALL SELECT 0.75 UNION ALL SELECT 0.80 UNION ALL SELECT 0.85
)
SELECT th.t AS threshold,
       SUM(st.c25 / st.c09 <  th.t) AS n_affected,
       SUM(st.c25 / st.c09 >= th.t) AS n_healthy,
       ROUND(100 * (POW(
             SUM(CASE WHEN st.c25 / st.c09 >= th.t THEN st.c25 END) /
             SUM(CASE WHEN st.c25 / st.c09 >= th.t THEN st.c00 END), 1.0 / 25) - 1), 3) AS healthy_cagr_pct
FROM st CROSS JOIN th
WHERE st.c09 > 0
GROUP BY th.t
ORDER BY th.t;
-- If healthy_cagr_pct barely moves between 0.65 and 0.80, the 0.70 choice is safe.

-- C9.2 Borderline states: ratio between 0.60 and 0.85 (these decide the groups)
SELECT state_code, state_name,
       ROUND(MAX(CASE WHEN year = 2025 THEN total_sales END) /
             NULLIF(MAX(CASE WHEN year = 2009 THEN total_sales END), 0), 3) AS ratio_2025_2009
FROM v_master
GROUP BY state_code, state_name
HAVING ratio_2025_2009 BETWEEN 0.60 AND 0.85
ORDER BY ratio_2025_2009;

-- C9.3 Anomaly threshold (year-over-year jump): rows flagged at each level
WITH chg AS (
    SELECT state_code, year,
           total_sales / NULLIF(LAG(total_sales) OVER (PARTITION BY state_code ORDER BY year), 0) - 1 AS d
    FROM v_consumption_wide
),
th AS (SELECT 0.20 AS t UNION ALL SELECT 0.30 UNION ALL SELECT 0.40 UNION ALL SELECT 0.50)
SELECT th.t AS threshold, COUNT(chg.d) AS rows_flagged
FROM th
LEFT JOIN chg ON ABS(chg.d) > th.t
GROUP BY th.t
ORDER BY th.t;

-- C9.4 Size threshold for carbon-intensity rankings: how many states qualify
SELECT th.min_twh,
       COUNT(m.state_code) AS states_included
FROM (SELECT 1 AS min_twh UNION ALL SELECT 5 UNION ALL SELECT 10 UNION ALL SELECT 20) th
LEFT JOIN v_master m ON m.year = 2025 AND m.total_generation_twh >= th.min_twh
GROUP BY th.min_twh
ORDER BY th.min_twh;

-- =====================================================================
-- PART D. EXPORT VIEWS (feed the notebook / dashboards)
-- =====================================================================

DROP VIEW IF EXISTS v_export_master;
CREATE VIEW v_export_master AS
SELECT * FROM v_master;

DROP VIEW IF EXISTS v_export_national;
CREATE VIEW v_export_national AS
SELECT year, generation_twh, renewable_twh, fossil_twh, emissions_mtco2e,
       consumption_twh_all, consumption_twh_healthy, consumption_twh_affected, population,
       100.0 * renewable_twh / NULLIF(generation_twh, 0)     AS renewable_share_pct,
       1000.0 * emissions_mtco2e / NULLIF(generation_twh, 0) AS carbon_intensity_g_kwh
FROM v_national_year;

DROP VIEW IF EXISTS v_export_generation_mix;
CREATE VIEW v_export_generation_mix AS
SELECT g.state_code, s.state_name, g.year, so.source_name, so.is_renewable, so.is_fossil,
       g.generation_twh, g.generation_share_pct,
       g.emissions_mtco2e, g.emissions_share_pct, g.emissions_intensity_gco2e_kwh
FROM fact_generation g
JOIN dim_state  s  ON s.state_code = g.state_code
JOIN dim_source so ON so.source_id = g.source_id;

SELECT * FROM v_export_master ORDER BY year, state_code;

-- =====================================================================
-- PART E. INSIGHTS
-- The queries above compute; this part answers five questions. Each question
-- points to the query that proves it. Run E1 first: it is the scoreboard.
--
--   Q1  Did US electricity get cleaner?
--       -> E1 rows 1-6 | C2.1 C2.2 C2.3 | C6.1 (why) | C6.2 (which states)
--   Q2  Did electricity demand decouple from economic growth?
--       -> E1 rows 7-10, 12 | C5.1 C5.2 C5.5 | C8.1 (by period)
--   Q3  Did electricity get more expensive in real terms?
--       -> E1 row 11 | C7.1 C7.2 C7.3 | C4.2 C4.3 (do states converge?)
--   Q4  Which states changed the most?
--       -> C3.5 C8.3 (demand) | C2.8 C2.9 C6.2 (supply) | C5.6 (exporters)
--   Q5  How far can we trust the data?
--       -> E1 rows 13-14 | C1.4 C1.5 C1.6 | C9.1 C9.2 C9.3
-- =====================================================================

-- E1. Scoreboard: one row per headline finding (values are computed, not typed)
SELECT insight_no, topic, insight, value, unit
FROM (
    -- ---- Q1: cleaner electricity ----
    SELECT 1 AS insight_no, 'Emissions' AS topic,
           'Power-sector emissions: change from first year of data to 2025' AS insight,
           ROUND(100 * (MAX(CASE WHEN year = 2025 THEN emissions_mtco2e END) /
                 NULLIF(MAX(CASE WHEN year = (SELECT MIN(year) FROM fact_generation) THEN emissions_mtco2e END), 0) - 1), 1) AS value,
           '%' AS unit
    FROM v_national_year
    UNION ALL
    SELECT 2, 'Generation', 'Total generation: change from first year of data to 2025',
           ROUND(100 * (MAX(CASE WHEN year = 2025 THEN generation_twh END) /
                 NULLIF(MAX(CASE WHEN year = (SELECT MIN(year) FROM fact_generation) THEN generation_twh END), 0) - 1), 1),
           '%'
    FROM v_national_year
    UNION ALL
    SELECT 3, 'Emissions', 'Carbon intensity of generation: change from first year to 2025',
           ROUND(100 * (MAX(CASE WHEN year = 2025 THEN emissions_mtco2e / generation_twh END) /
                 NULLIF(MAX(CASE WHEN year = (SELECT MIN(year) FROM fact_generation) THEN emissions_mtco2e / generation_twh END), 0) - 1), 1),
           '%'
    FROM v_national_year
    UNION ALL
    SELECT 4, 'Mix', 'Renewable share of generation: change from first year to 2025',
           ROUND(MAX(CASE WHEN year = 2025 THEN 100 * renewable_twh / generation_twh END) -
                 MAX(CASE WHEN year = (SELECT MIN(year) FROM fact_generation) THEN 100 * renewable_twh / generation_twh END), 1),
           'pp'
    FROM v_national_year
    UNION ALL
    SELECT 5, 'Mix', 'Coal share of generation: change from first year to 2025',
           ROUND(100 * SUM(CASE WHEN g.year = 2025 AND s.source_name = 'Coal' THEN g.generation_twh END) /
                       SUM(CASE WHEN g.year = 2025 THEN g.generation_twh END) -
                 100 * SUM(CASE WHEN g.year = (SELECT MIN(year) FROM fact_generation) AND s.source_name = 'Coal' THEN g.generation_twh END) /
                       SUM(CASE WHEN g.year = (SELECT MIN(year) FROM fact_generation) THEN g.generation_twh END), 1),
           'pp'
    FROM fact_generation g
    JOIN dim_source s ON s.source_id = g.source_id
    UNION ALL
    SELECT 6, 'Mix', 'Wind + solar share of generation in 2025',
           ROUND(100 * SUM(CASE WHEN g.year = 2025 AND s.source_name IN ('Wind', 'Solar') THEN g.generation_twh END) /
                       SUM(CASE WHEN g.year = 2025 THEN g.generation_twh END), 1),
           '%'
    FROM fact_generation g
    JOIN dim_source s ON s.source_id = g.source_id
    -- ---- Q2: demand vs economy (healthy states only) ----
    UNION ALL
    SELECT 7, 'Demand', 'Electricity consumption growth, 37 healthy states, 2000-2025 (CAGR)',
           ROUND(100 * (POW(MAX(CASE WHEN year = 2025 THEN twh END) /
                            MAX(CASE WHEN year = 2000 THEN twh END), 1.0 / 25) - 1), 2),
           '% per year'
    FROM v_cons_series
    WHERE scope = 'healthy_37'
    UNION ALL
    SELECT 8, 'Demand', 'Electricity per person, healthy states: change 2000 to 2025',
           ROUND(100 * ((SUM(CASE WHEN year = 2025 THEN total_sales END) / SUM(CASE WHEN year = 2025 THEN population END)) /
                        (SUM(CASE WHEN year = 2000 THEN total_sales END) / SUM(CASE WHEN year = 2000 THEN population END)) - 1), 1),
           '%'
    FROM v_master
    WHERE affected_break = 0
    UNION ALL
    SELECT 9, 'Economy', 'Real GDP growth, healthy states (excl. DC), 2000-2025 (CAGR)',
           ROUND(100 * (POW(SUM(CASE WHEN year = 2025 THEN real_gdp_musd2017 END) /
                            SUM(CASE WHEN year = 2000 THEN real_gdp_musd2017 END), 1.0 / 25) - 1), 2),
           '% per year'
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC'
    UNION ALL
    SELECT 10, 'Decoupling', 'Electricity needed per real GDP dollar: change 2000 to 2025',
           ROUND(100 * ((SUM(CASE WHEN year = 2025 THEN total_sales END) / SUM(CASE WHEN year = 2025 THEN real_gdp_musd2017 END)) /
                        (SUM(CASE WHEN year = 2000 THEN total_sales END) / SUM(CASE WHEN year = 2000 THEN real_gdp_musd2017 END)) - 1), 1),
           '%'
    FROM v_master
    WHERE affected_break = 0 AND state_code <> 'DC'
    -- ---- Q3: real prices ----
    UNION ALL
    SELECT 11, 'Prices', 'Real residential price (2025 dollars): change 2000 to 2025',
           ROUND(100 * ((SUM(CASE WHEN m.year = 2025 THEN m.res_revenues END) / SUM(CASE WHEN m.year = 2025 THEN m.res_sales END)) /
                        (SUM(CASE WHEN m.year = 2000 THEN m.res_revenues END) / SUM(CASE WHEN m.year = 2000 THEN m.res_sales END)) *
                        MAX(CASE WHEN y.year = 2000 THEN y.cpi_u END) / MAX(CASE WHEN y.year = 2025 THEN y.cpi_u END) - 1), 1),
           '%'
    FROM v_master m
    JOIN dim_year y ON y.year = m.year
    WHERE m.year IN (2000, 2025)
    UNION ALL
    SELECT 12, 'Decoupling', 'Healthy states where consumption fell or stayed flat while real GDP grew',
           COUNT(*), 'states'
    FROM (
        SELECT state_code,
               MAX(CASE WHEN year = 2025 THEN total_sales END) /
               NULLIF(MAX(CASE WHEN year = 2000 THEN total_sales END), 0)        AS cons_ratio,
               MAX(CASE WHEN year = 2025 THEN real_gdp_musd2017 END) /
               NULLIF(MAX(CASE WHEN year = 2000 THEN real_gdp_musd2017 END), 0)  AS gdp_ratio
        FROM v_master
        WHERE affected_break = 0 AND state_code <> 'DC'
        GROUP BY state_code
    ) t
    WHERE cons_ratio <= 1 AND gdp_ratio > 1
    -- ---- Q5: data reliability ----
    UNION ALL
    SELECT 13, 'Data quality', 'Share of 2009 national consumption in the states later flagged with a break',
           ROUND(100 * SUM(CASE WHEN affected_break = 1 THEN total_sales END) / SUM(total_sales), 1),
           '%'
    FROM v_master
    WHERE year = 2009
    UNION ALL
    SELECT 14, 'Data quality', 'States excluded from consumption trends (break flag)',
           COUNT(*), 'states'
    FROM v_state_break
    WHERE affected_break = 1
) i
ORDER BY insight_no;

-- E2. The states behind the story: top 3 of each, side by side
(SELECT 'Largest emission cut (Mt)' AS finding, state_code, state_name, ROUND(change_mt, 1) AS value
 FROM (
    SELECT m.state_code, m.state_name,
           MAX(CASE WHEN m.year = 2025 THEN m.total_emissions_mtco2e END) -
           MAX(CASE WHEN m.year = (SELECT MIN(year) FROM fact_generation) THEN m.total_emissions_mtco2e END) AS change_mt
    FROM v_master m
    WHERE m.total_generation_twh >= 5
    GROUP BY m.state_code, m.state_name
 ) a
 WHERE change_mt IS NOT NULL
 ORDER BY change_mt ASC LIMIT 3)
UNION ALL
(SELECT 'Fastest demand growth, healthy states (% 2000-2025)', state_code, state_name, ROUND(growth_pct, 1)
 FROM (
    SELECT state_code, state_name,
           100 * (SUM(CASE WHEN year = 2025 THEN total_sales END) /
                  NULLIF(SUM(CASE WHEN year = 2000 THEN total_sales END), 0) - 1) AS growth_pct
    FROM v_master
    WHERE affected_break = 0
    GROUP BY state_code, state_name
 ) b
 WHERE growth_pct IS NOT NULL
 ORDER BY growth_pct DESC LIMIT 3)
UNION ALL
(SELECT 'Highest renewable share in 2025 (%, states above 5 TWh)', state_code, state_name, ROUND(renewable_share_pct, 1)
 FROM v_master
 WHERE year = 2025 AND total_generation_twh >= 5 AND renewable_share_pct IS NOT NULL
 ORDER BY renewable_share_pct DESC LIMIT 3)
UNION ALL
(SELECT 'Biggest real residential price rise (%)', state_code, state_name, real_change_pct
 FROM (
    SELECT m.state_code, m.state_name,
           ROUND(100 * (MAX(CASE WHEN m.year = 2025 THEN m.p_res END) /
                 NULLIF(MAX(CASE WHEN m.year = 2000 THEN m.p_res * r.cpi_u / c.cpi_u END), 0) - 1), 1) AS real_change_pct
    FROM v_master m
    JOIN dim_year c ON c.year = m.year
    JOIN dim_year r ON r.year = 2025
    WHERE m.year IN (2000, 2025) AND m.p_res IS NOT NULL
    GROUP BY m.state_code, m.state_name
 ) c
 WHERE real_change_pct IS NOT NULL
 ORDER BY real_change_pct DESC LIMIT 3);

-- =====================================================================
-- END
-- =====================================================================
