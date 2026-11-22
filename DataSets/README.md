# Dataset Documentation

## Overview

This directory contains the unified dataset used in the U.S. Electricity Consumption & Generation Analysis project.

The dataset integrates electricity, economic, environmental, and demographic data across U.S. states, covering 2000–2025.

## Main File

| File | Description |
|---|---|
| `unified_dataset.csv` | Final cleaned and integrated dataset. |

## Data Sources

### 1. U.S. Energy Information Administration (EIA)
Website: https://www.eia.gov/electricity/data.php

Used for electricity consumption and retail sales data, including:
- Total electricity sales.
- Residential, commercial, and industrial sales.
- Electricity revenues.
- Average retail electricity prices.
- Electricity customers.

### 2. Ember
Website: https://ember-energy.org/data/us-electricity-data/

Used for state-level electricity generation and emissions data, including:
- Electricity generation by energy source.
- Generation shares.
- Greenhouse gas emissions.
- Emissions intensity.

### 3. U.S. Bureau of Economic Analysis (BEA)
Website: https://www.bea.gov/data/gdp/gdp-state

Used for state-level economic indicators, including:
- Real GDP.
- Current-dollar GDP.
- GDP components.
- GDP per capita (calculated during data processing).

### 4. FRED – Federal Reserve Economic Data
Website: https://fred.stlouisfed.org/release?rid=118

Used for annual state-level resident population estimates.

Population data was collected using web scraping from FRED.

**Original data provider:** U.S. Census Bureau.

## Data Preparation

The original datasets were processed and integrated through:

1. Data cleaning and duplicate removal.
2. Standardization of state names, codes, and years.
3. Handling missing and inconsistent values.
4. Reshaping generation and emissions data by energy source.
5. Integrating datasets using Year and State Code.
6. Calculating additional indicators such as GDP per capita.

The final dataset maintains one record per state-year combination.

## Important Notes

- The national aggregate (`US`) is excluded from state-level summations to avoid double counting.
- The `affected_break` indicator identifies states affected by discontinuities in reported electricity sales.
- Data availability varies across sources and indicators.
- Original data providers may revise historical records.

## Usage

The unified dataset serves as the primary input for the Python analysis and interactive dashboard.
