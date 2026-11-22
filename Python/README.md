# US Electricity, Economy, and Population Analysis by State (2000–2025)

A comprehensive, state-level data engineering, statistical, and power-system engineering analysis examining the evolution of electricity generation, retail consumption, pricing, carbon emissions, GDP, and population across the United States from 2000 to 2025.

---

## 📋 Table of Contents
- [Executive Summary & Headline Findings](#executive-summary--headline-findings)
- [Project Structure & Methodology](#project-structure--methodology)
- [Data Sources](#data-sources)
- [Key Equations & Engineering Metrics](#key-equations--engineering-metrics)
- [Data Quality Notes](#data-quality-notes)
- [Getting Started & Prerequisites](#getting-started--prerequisites)
- [Usage](#usage)

---

## 🔍 Executive Summary & Headline Findings

This project cleans, merges, and analyzes four multi-decade state-level datasets into a unified state-year panel (`unified_dataset.csv`):

* **Transformation of the Generation Mix:** Coal plummeted from **51.1%** of total US electricity generation in 2001 to **16.3%** in 2025. Natural gas expanded from **17.1%** to **40.0%**, while wind and solar surged from **~0.2%** to **18.9%**.
* **Flat Demand vs. Rising Nominal Prices:** Total US retail electricity consumption remained nearly flat (**3,421 TWh** in 2000 vs. **3,480 TWh** in 2025). However, the sales-weighted average retail price climbed **+90%** (from **6.81** to **12.98 cents/kWh** nominal), with residential rates doubling.
* **Decarbonization Drivers (Kaya / LMDI Decomposition):** Emissions reductions were driven primarily by cleaner generation (lower carbon intensity per kWh) rather than reduced electricity demand.
* **Divergent State Transitions:** States followed distinct decarbonization pathways—industrial states like Ohio and Pennsylvania shifted predominantly toward natural gas, whereas states like Iowa and New Mexico transitioned heavily into wind and solar.

---

## 🛠️ Project Structure & Methodology

The Jupyter Notebook is organized into nine structured sections:
1. **Introduction & Nomenclature:** Context, scope definitions (50 states + DC; US totals removed to prevent double counting), and engineering equations.
2. **Environment Setup:** Library imports and cross-environment relative path discovery (`find()`).
3. **Data Cleaning & Preparation:** Standardizing column headers, mapping state codes, reshaping wide BEA GDP tables to long format, checking completeness, and exporting clean intermediate tables (`consumption_clean.csv`, `gdp_clean.csv`, etc.).
4. **Generation & Consumption Statistics:** Sectoral sales, revenues, prices, and anomaly detection.
5. **Population & GDP Statistics:** Economic growth (real vs. nominal) and demographic correlations.
6. **Visualization & Insights:** Time-series, state comparisons, and structural shifts.
7. **Power-System Engineering Analysis:** Capacity factors, average power ($GW$), Herfindahl–Hirschman Index ($HHI$), Shannon diversity entropy ($H$), emission intensities, and Kaya/LMDI decomposition.
8. **Key Insights & Conclusions:** Actionable takeaways for energy analysts and policymakers.
9. **Limitations & Recommended Extensions:** Inflation adjustment guidelines and structural reporting caveats.

---

## 📊 Data Sources

| Dataset File | Description | Units | Period |
| :--- | :--- | :--- | :--- |
| `consumption.csv` | Retail sales, revenues, customer counts, and prices by sector (Residential, Commercial, Industrial) | MWh, Thousand USD, Cents/kWh | 2000–2025 |
| `GDP__ALL_AREAS_1997_2025.csv` | Current-dollar and Real GDP (chained 2017 USD) and income components by state | Million USD | 1997–2025 *(2000–2025 used)* |
| `release_us_subnational_generation_yearly.csv` | Electricity generation, fuel shares, CO₂e emissions, and emission intensity by fuel source | TWh, MtCO₂e, gCO₂e/kWh | 2001–2025 |
| `population_long.csv` | Annual resident population by state | Persons | 2000–2025 |

---

## 📐 Key Equations & Engineering Metrics

* **Sales-Weighted Price:** $\bar{p} = \frac{\sum R_i}{\sum S_i} \times 100$ *(cents/kWh)*
* **System Consumption-to-Generation Ratio:** $\eta_{sys} = \frac{S}{G} \times 100$ *(%)*
* **Emission Intensity:** $I = \frac{E^{CO_2e}}{G} \times 1000$ *(gCO₂e/kWh)*
* **Average Power:** $P_{avg} = \frac{E \times 1000}{8760}$ *(GW)*
* **Fuel Mix Concentration & Diversity:** Herfindahl–Hirschman Index ($HHI = \sum (100 s_i)^2$) and Shannon Entropy ($H = -\sum s_i \ln s_i$)
* **Kaya Identity & LMDI Decomposition:** $C = N \cdot \frac{Y}{N} \cdot \frac{G}{Y} \cdot \frac{C}{G}$

---

## ⚠️ Data Quality Notes

* **Retail Sales Structural Break (`affected_break`):** Starting around 2010, **14 states** exhibit a sharp drop in reported retail sales (with their consumption-to-generation ratio dropping from ~99% to 52–67%, while the remaining 37 states stay near ~88%). Because this reflects a utility/retail-choice reporting artifact rather than an actual demand collapse, those 14 states are explicitly flagged and analyzed separately.
* **Nominal Prices:** Retail electricity prices are reported in nominal cents/kWh and should be adjusted for inflation when evaluating real cost trends.

---

## ⚙️ Getting Started & Prerequisites

### Python Environment
Tested with:
* Python 3.10+
* `pandas` (v3.0.5)
* `numpy` (v2.2.0)
* `matplotlib`
* `seaborn`
* `jupyter`

Install dependencies via pip:
```bash
pip install pandas numpy matplotlib seaborn jupyter

---

### note: before running the code make sure to contain both the data and this file in the same folder.

