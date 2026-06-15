# Structured Note Pricing & Hedging under the LMM

MATLAB implementation of the full pricing and risk-management pipeline for a structured note with embedded interest rate caps, calibrated under the **Libor Market Model (LMM)**.

## Overview

The project prices a capped structured note and computes its Greeks (Delta and Vega) using a bootstrapped discount curve and LMM spot volatilities stripped from market cap prices. It then builds Delta and Vega hedges using IRS and vanilla caps.

### Key steps

1. **Curve bootstrapping** – Discount factors and zero rates are stripped from deposits, futures and swap quotes stored in `MktData_CurveBootstrap.xls`.
2. **Forward LIBOR curve** – Quarterly forward LIBORs are computed up to 20 years.
3. **LMM calibration** – Spot volatilities are stripped bucket-by-bucket from market flat-vol cap prices via root-finding (`fzero`), with linear interpolation between pillar dates.
4. **Upfront pricing** – The fair upfront fee *X* is computed by equating the NPV of the fixed coupon stream to the embedded cap portfolio, with an optional digital-risk correction.
5. **Delta (DV01)** – Fine-bucket and coarse-grained DV01 are computed by bumping each bootstrap instrument by 1 bp; a hedge with 2Y/6Y/10Y payer IRS is then solved via linear system inversion.
6. **Vega** – Total and bucketed Vega are computed by bumping flat volatilities; a hedge with 6Y and 10Y ATM caps (and variants) is solved analogously.

## Repository structure

```
.
├── RunAssignment.m              # Main script – runs all exercises end-to-end
├── calibrateLMMSpotVols.m       # LMM spot-vol stripping via bucket bootstrapping
├── computeCapPricesFlat.m       # Cap pricing under flat Black volatilities
├── computeForwardLibors.m       # Forward LIBOR curve construction
├── computeUpfrontX.m            # Upfront fee pricing (w/ and w/o digital correction)
├── computeDeltaBuckets.m        # Fine and coarse DV01 computation
├── ComputeVega.m                # Vega computation (total and bucketed)
├── DeltaHedge.m                 # IRS Delta hedge
├── VegaHedge.m                  # Cap Vega hedge
└── utilities_bootstrap/
    ├── bootstrap.m              # Curve bootstrapping
    ├── fromdatetodiscount.m     # Discount factor interpolation
    ├── ConvertDates.m           # Date utilities
    ├── readExcelData_mac.m      # Excel reader (macOS)
    ├── readExcelData_windows.m  # Excel reader (Windows)
    └── MktData_CurveBootstrap.xls  # Market data (deposits, futures, swaps)
```

## Requirements

- MATLAB R2021a or later
- Financial Toolbox (for `blkprice`, `yearfrac`, `bootstrap`)

## Usage

Open MATLAB, set the project root as the working directory, and run:

```matlab
RunAssignment
```

The script prints the upfront fee *X*, DV01 tables and hedge notionals to the console, and generates plots for the Delta and Vega hedge results.

## Methods

| Component | Approach |
|---|---|
| Curve bootstrapping | Piecewise-constant instantaneous forward rates |
| Cap pricing | Black-76 (flat vol surface) |
| LMM calibration | Bucket bootstrapping + `fzero` root-finding |
| Spot-vol interpolation | Linear in reset time between consecutive pillars |
| Delta computation | Parallel bump of individual bootstrap instruments (+1 bp) |
| Vega computation | Parallel bump of flat volatility surface (+1 vol point) |
| Hedging | Linear system inversion (`A \ b`) |
