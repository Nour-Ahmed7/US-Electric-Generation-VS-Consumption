# US Electricity Project — MySQL Data Warehouse & Analytical Queries (2000–2025)

A complete, end-to-end MySQL relational data warehouse (`us_energy`) implementing a **Fact Constellation (Galaxy) Schema**, automated data loading and reconciliation checks, analytical views, and advanced econometric/energy-system queries (LMDI decomposition, real price deflation, decoupling, and sensitivity analysis) across 50 US states + DC from 2000 to 2025.

> **📌 Important Note:** This SQL script runs directly on the **attached pre-cleaned datasets** (`consumption_clean.csv`, `gdp_clean.csv`, `population_long.csv`, `us_state_generation_clean.csv`, and `us_state_emissions_clean.csv`). You do **not** need to run any raw-data preprocessing beforehand or import `unified_dataset.csv`—simply import these five cleaned CSV files into the `us_energy` database, and the script will automatically build and populate the entire schema[cite: 2].

---

## 📋 Table of Contents
- [Database Architecture (Fact Constellation Schema)](#database-architecture-fact-constellation-schema)
- [Script Structure (Parts A–E)](#script-structure-parts-ae)
- [Input Staging Tables (Attached Cleaned Data)](#input-staging-tables-attached-cleaned-data)
- [Key Analytical Views](#key-analytical-views)
- [Data Quality & Methodological Rules](#data-quality--methodological-rules)
- [Usage & Execution Guide](#usage--execution-guide)

---

## 🏗️ Database Architecture (Fact Constellation Schema)

The `us_energy` database models supply, demand, and macroeconomic context using **3 Fact Tables** linked across **4 Shared Dimension Tables** (8 foreign-key relationships in total)[cite: 2]:

### Dimension Tables
* `dim_state`: One row per jurisdiction (`state_code` PK, `state_name`) — 50 states + DC (`US` and `PR` aggregates excluded)[cite: 2].
* `dim_year`: Study timeline `2000–2025` (`year` PK) paired with annual **CPI-U** (`1982–84 = 100`) for inflation adjustment[cite: 2].
* `dim_source`: Electricity generation fuel sources (`source_id` PK, `source_name`, `is_renewable`, `is_fossil`)[cite: 2].
* `dim_sector`: Retail consumption sectors (`Residential`, `Commercial`, `Industrial`, and `Total` flagged via `is_total = 1`)[cite: 2].

### Fact Tables
* `fact_generation` *(Supply)*: Grain `(state_code, year, source_id)` — stores generation (`TWh`), generation share (`%`), emissions (`MtCO2e`), emission share (`%`), and carbon intensity (`gCO2e/kWh`)[cite: 2].
* `fact_consumption` *(Demand)*: Grain `(state_code, year, sector_id)` — unpivots wide sectoral columns into long format storing revenues (`thousand USD`), sales (`MWh`), customers, and nominal price (`cents/kWh`)[cite: 2].
* `fact_economy` *(Context)*: Grain `(state_code, year)` — stores population, Real GDP (`chained 2017 million USD`), Current-Dollar GDP, employee compensation, gross operating surplus, and taxes on production/imports less subsidies[cite: 2].

---

## 📂 Script Structure (Parts A–E)

The SQL script (`FF_us_energy_project_final.sql`) is organized into five self-contained sections[cite: 2]:

1. **Part A — Schema, Load & Reconciliation Checks:**
   * Builds all dimension and fact tables with InnoDB foreign keys and indexes[cite: 2].
   * Populates tables directly from the 5 attached cleaned CSV staging tables[cite: 2].
   * Runs automated audit queries (`A.-1` through `A.5`) verifying foreign keys (8 expected), staging row counts, and zero row loss[cite: 2].
2. **Part B — Analytical Views (`v_*`):**
   * Abstracts joins, unit conversions, structural-break flags, and weighted price formulas into clean reusable views[cite: 2].
3. **Part C — Core Analytical Queries (`C1–C9`):**
   * `C1`: Data quality, missing values, structural break identification, and YoY anomaly detection (`>40%`)[cite: 2].
   * `C2`: Generation mix shifts, renewable shares, carbon intensity rankings, and coal declines[cite: 2].
   * `C3`: Sectoral consumption trends, CAGR, linear regression slopes ($R^2$), and per-capita consumption[cite: 2].
   * `C4`: Sales-weighted nominal prices and cross-state price dispersion (Coefficient of Variation)[cite: 2].
   * `C5`: Economic electricity intensity (`kWh/$`), Pearson $r$ & Spearman $\rho$ correlations, and GDP-electricity decoupling[cite: 2].
   * `C6`: **LMDI Decomposition** (activity, fuel mix, and emission-factor effects) and Shapley state-level decomposition[cite: 2].
   * `C7`: **Real Price Deflation** (converting nominal `cents/kWh` into constant 2025 USD via `dim_year.cpi_u`)[cite: 2].
   * `C8`: Sub-period regime analysis (`2000–2007` growth, `2007–2019` plateau, `2019–2025` recent trends)[cite: 2].
   * `C9`: Sensitivity & robustness checks across break thresholds (`0.60–0.85`), anomaly cutoffs, and generation size filters[cite: 2].
4. **Part D — Export Views:**
   * Provides clean views (`v_export_master`, `v_export_national`, `v_export_generation_mix`) ready for Python notebooks or BI dashboards (Tableau / Power BI)[cite: 2].
5. **Part E — Executive Insights & Scoreboard (`E1–E2`):**
   * Dynamically computes 14 headline KPI findings (`E1`) and top-3 state leaderboards (`E2`) directly from the underlying schema[cite: 2].

---

## 📥 Input Staging Tables (Attached Cleaned Data)

Import the **five attached cleaned CSV files** into the `us_energy` database under identical table names before running `FF_us_energy_project_final.sql`[cite: 2]:

| Staging Table Name | Attached Cleaned CSV File | Expected Rows |
| :--- | :--- | :--- |
| `consumption_clean` | `consumption_clean.csv` | 1,352[cite: 2] |
| `gdp_clean` | `gdp_clean.csv` | —[cite: 2] |
| `population_long` | `population_long.csv` | —[cite: 2] |
| `us_state_generation_clean` | `us_state_generation_clean.csv` | 9,586[cite: 2] |
| `us_state_emissions_clean` | `us_state_emissions_clean.csv` | 9,586[cite: 2] |

---

## 👁️ Key Analytical Views

* `v_consumption_wide`: Pivots `fact_consumption` back into one wide row per `(state_code, year)`[cite: 2].
* `v_state_break`: Flags states (`affected_break = 1`) whose 2025 reported retail sales fell below 70% of 2009 levels due to retail-choice reporting artifacts (14 affected states vs. 37 healthy states)[cite: 2].
* `v_gen_state_year`: Aggregates generation (`TWh`), renewable/fossil/coal totals, and emissions (`MtCO2e`) per state-year[cite: 2].
* `v_master`: Complete `51 states × 26 years` (`1,326` rows) analytical panel joining economy, consumption, weighted prices, generation, carbon intensity, and net exports[cite: 2].
* `v_national_year` & `v_cons_series`: Bottom-up national totals aggregated strictly from state rows (split into `healthy_37`, `affected_14`, and `all_51`)[cite: 2].

---

## ⚠️ Data Quality & Methodological Rules

* **Structural Break Filtering:** All longitudinal demand and decoupling queries filter on `affected_break = 0` (`37` healthy states) to prevent retail-choice reporting drops from distorting national consumption trends[cite: 2].
* **Bottom-Up National Totals:** Aggregate rows (`US` and `PR`) are excluded during ingestion (`Part A`) so national metrics are always summed consistently from state-level records without double-counting[cite: 2].
* **MySQL Workbench EER Diagrams:** Analytical views (`v_*`) appear as yellow objects without foreign-key lines; untick **Views** and staging tables when reverse-engineering to inspect the clean star/constellation schema[cite: 2].

---

## 🚀 Usage & Execution Guide

1. **Create Database & Import Attached Cleaned CSVs:**
   Create the `us_energy` schema in MySQL 8.0+ (required for CTEs and window functions like `LAG()` and `RANK()`) and import the **5 attached cleaned CSV files**[cite: 2].
2. **Execute the Script:**
   Run `FF_us_energy_project_final.sql` sequentially in MySQL Workbench or via CLI[cite: 2]:
   ```bash
   mysql -u root -p us_energy < FF_us_energy_project_final.sql
