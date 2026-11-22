# Cleaned Datasets (`cleaned_data/`)

This folder contains the pre-cleaned, standardized state-level datasets (50 US states + DC, covering 2000–2025) exported from the Jupyter Notebook preprocessing pipeline and ready for direct ingestion into the MySQL data warehouse (`FF_us_energy_project_final.sql`) or downstream BI dashboards[cite: 1, 2].

---

## 📁 Included Files

| File Name | Description | Key Columns & Units | Expected Rows |
| :--- | :--- | :--- | :--- |
| `consumption_clean.csv` | Standardized retail electricity sales, revenues, customer counts, and nominal prices by sector (Residential, Commercial, Industrial, Total)[cite: 1, 2] | `state_code`, `year`, `res_sales` (`MWh`), `res_revenues` (`thousand USD`), `res_price` (`cents/kWh`)[cite: 1, 2] | 1,352[cite: 2] |
| `gdp_clean.csv` | Reshaped long-format state GDP and macroeconomic income components (2000–2025)[cite: 1, 2] | `state_code`, `state_name`, `year`, `real_gdp_musd2017` (`million chained 2017 USD`), `gdp_current_musd` (`million USD`)[cite: 2] | — |
| `population_long.csv` | Annual resident population by state (2000–2025)[cite: 1, 2] | `state_code`, `state`, `year`, `population` (`persons`)[cite: 1, 2] | — |
| `us_state_generation_clean.csv` | State-level electricity generation and fuel mix shares by energy source (2001–2025)[cite: 1, 2] | `State code`, `Year`, `Electricity source`, `Generation (TWh)`, `Share of generation (%)`[cite: 2] | 9,586[cite: 2] |
| `us_state_emissions_clean.csv` | State-level power-sector greenhouse gas emissions and carbon intensity by fuel source (2001–2025)[cite: 1, 2] | `State code`, `Year`, `Electricity source`, `Emissions (MtCO2e)`, `Emissions intensity (gCO2e/kWh)`[cite: 2] | 9,586[cite: 2] |

*(Note: `unified_dataset.csv`—if present—is generated for convenience in Python, whereas the SQL script rebuilds the master state-year grid directly from the five tables listed above[cite: 1, 2].)*

---

## 🛠️ Preprocessing Applied

* **Standardized Identifiers:** Two-letter USPS state codes (`state_code`) mapped consistently across all tables[cite: 1, 2].
* **Reshaped Structure:** Wide BEA GDP tables melted into long `(state_code, year)` format[cite: 1, 2].
* **Type & Header Normalization:** Clean column names, numeric data types enforced, and trailing whitespace removed[cite: 1, 2].
* **Aggregate Handling:** National (`US`) and territory (`PR`) aggregate rows are filtered out during SQL ingestion (`Part A`) to prevent double-counting[cite: 2].

---

## 🚀 How to Use with SQL

1. Create the `us_energy` database in MySQL 8.0+[cite: 2].
2. Import the **five CSV files** listed in the table above into `us_energy` keeping their exact filenames as table names[cite: 2].
3. Run `FF_us_energy_project_final.sql` and verify the load counts in **Part A (`A.0`–`A.5`)**[cite: 2].
