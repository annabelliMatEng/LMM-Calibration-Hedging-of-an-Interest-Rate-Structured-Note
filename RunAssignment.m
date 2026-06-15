clc; close all; clear all

addpath(fullfile(pwd, 'utilities_bootstrap'));

%% Parameters

mkt = struct();

mkt.strikes = [1.50 1.75 2.00 2.25 2.50 3.00 3.50 ...
               4.00 5.00 6.00 7.00 8.00 10.00] / 100;

mkt.maturities = [1 2 3 4 5 6 7 8 9 10 12 15 20];

mkt.flatVolPct = [
    14.0 13.0 12.9 12.1 13.3 13.8 14.4 15.0 17.2 19.1 20.2 21.6 23.9
    22.4 19.7 17.5 18.0 19.2 20.4 21.0 21.4 22.3 23.6 24.9 26.1 28.1
    23.8 21.7 20.0 19.8 20.3 20.5 20.8 21.4 22.9 24.3 25.6 26.7 28.2
    24.2 22.4 20.9 20.4 20.4 20.2 20.2 20.5 21.7 22.9 24.0 25.0 26.6
    24.3 22.6 21.2 20.6 20.4 19.8 19.5 19.6 20.5 21.5 22.6 23.5 25.0
    24.3 22.7 21.4 20.7 20.2 19.4 18.9 18.8 19.3 20.2 21.2 22.0 23.5
    24.1 22.6 21.4 20.7 20.1 19.1 18.4 18.1 18.4 19.1 20.0 20.8 22.2
    23.9 22.5 21.4 20.6 20.0 18.8 18.0 17.6 17.6 18.2 19.0 19.8 21.1
    23.7 22.4 21.3 20.5 19.8 18.5 17.6 17.1 17.0 17.6 18.3 19.0 20.3
    23.5 22.2 21.2 20.4 19.6 18.3 17.3 16.8 16.5 16.9 17.6 18.3 19.5
    23.0 21.7 20.8 20.0 19.3 17.9 16.9 16.2 15.8 16.0 16.5 17.1 18.1
    22.3 21.2 20.3 19.5 18.7 17.3 16.3 15.5 15.0 15.1 15.5 16.0 16.9
    21.6 20.4 19.5 18.8 18.0 16.6 15.5 14.7 14.1 14.1 14.5 15.0 15.9
];

mkt.flatVol = mkt.flatVolPct / 100;

mkt.strikeNames = {'K_1_50','K_1_75','K_2_00','K_2_25','K_2_50', ...
                   'K_3_00','K_3_50','K_4_00','K_5_00','K_6_00', ...
                   'K_7_00','K_8_00','K_10_00'};

mkt.maturityNames = {'1Y','2Y','3Y','4Y','5Y','6Y','7Y','8Y','9Y', ...
                     '10Y','12Y','15Y','20Y'};

mkt.flatVolTable = array2table(mkt.flatVolPct, ...
    'VariableNames', mkt.strikeNames, ...
    'RowNames', mkt.maturityNames);

disp(mkt.flatVolTable)

%% Retrieve Bootstrap

formatDate = 'dd/mm/yyyy';

formatDate = 'dd/mm/yyyy'; 
if ispc
    fprintf('Operating System: Windows detected. Loading data...\n');
    [datesSet, ratesSet] = readExcelData_windows('MktData_CurveBootstrap.xls', formatDate);
    
elseif ismac
    fprintf('Operating System: macOS detected. Loading data...\n');
    [datesSet, ratesSet] = readExcelData_mac('MktData_CurveBootstrap.xls', formatDate);
    
else
    error('Unsupported Operating System. Please use Windows or macOS.');
end

[curveDates, discounts, zeroRates] = bootstrap(datesSet, ratesSet);

t0 = datesSet.settlement;

% Contractual start date from termsheet
startDate = datetime('19-Feb-2008');

% Contractual maturity: 10 years after start date
maturityDate = ConvertDates(startDate + calyears(10));

%% Forward Libor curve and cap prices

% Define the grid up to 20 years
maturity_20y = startDate + calyears(20);
caplet_dates = (startDate : calmonths(3) : maturity_20y)';

adj_caplet_dates = ConvertDates(caplet_dates);

% Compute Forward Libor list
[forward_list, delta, B_grid] = computeForwardLibors(t0, curveDates, zeroRates, adj_caplet_dates);

% structure of outputs : forward_list goes from L(t0,t1) to L(t0,tn-1,tn)
%                        delta goes from d(t0,t1) to d(tN-1,tN)
%                        B_grid from B(t0,t0) to B(t0,tN)

% Prepare T_reset (Act/365)
T_reset = yearfrac(t0, adj_caplet_dates(2:end-1), 3);

% Compute Cap Prices using Flat volatilities
capPrices_mkt = computeCapPricesFlat(mkt, forward_list, B_grid, delta, T_reset);

%% Common parameters

bumpVega = 1e-2;   % 1 vol point shift 

%% Exercise 1.a) - LMM Calibration

spotVolStruct = calibrateLMMSpotVols(mkt, forward_list, B_grid, ...
                                     delta, T_reset, capPrices_mkt);

matrix       = spotVolStruct.spotVol;        % 79 x 13
pillarSigmas = spotVolStruct.pillarSigmas;   % 13 x 13

%% Exercise 1.b) & 1.g) - Upfront Pricing (with and without digital risk correction)

[X_pct_no_correction, NPV_fixed, NPV_coupons] = computeUpfrontX(matrix, mkt.strikes, forward_list, B_grid, delta, T_reset, 0);
[X_pct_corrected,     ~,         ~]           = computeUpfrontX(matrix, mkt.strikes, forward_list, B_grid, delta, T_reset, 1);

fprintf('X without digital risk correction: %.4f%%\n', X_pct_no_correction * 100);
fprintf('X with digital risk correction:    %.4f%%\n', X_pct_corrected     * 100);

%% Exercise 1.c) - Fine bucket Delta DV01

deltaBucketsFine = computeDeltaBuckets(datesSet, ratesSet, mkt, matrix, ...
                                       adj_caplet_dates, T_reset, X_pct_no_correction, "single");

disp('Fine bucket DV01:')
disp(deltaBucketsFine)

%% Exercise 1.d) - Total Vega

bucketsTotal = ones(size(mkt.flatVol));
totalVega    = ComputeVega(bumpVega, bucketsTotal, mkt, forward_list, B_grid, ...
                           delta, T_reset, X_pct_no_correction);

fprintf('\nComputed Total Vega (per 1 vol unit): %.6f\n', totalVega);

%% Exercise 1.e) - Coarse-grained Delta DV01 and Delta hedge

deltaBucketsCoarse = computeDeltaBuckets(datesSet, ratesSet, mkt, matrix, ...
                                         adj_caplet_dates, T_reset, X_pct_no_correction, "coarse");

disp('Coarse-grained bucket DV01:')
disp(deltaBucketsCoarse)

yearListDelta = [2; 6; 10];

[hedgeNotionalsDelta, A_delta, residualDV01] = DeltaHedge(yearListDelta, datesSet, ratesSet, deltaBucketsCoarse.DV01_EUR);

disp('Delta hedge notionals:')
disp(hedgeNotionalsDelta)

disp('Residual DV01 after Delta hedge:')
disp(residualDV01)

%% Exercise 1.f) - Vega Hedge with 6Y and 10Y caps

yearListVega   = [6, 10];
mask_0_6       = (mkt.maturities <= 6)';
mask_6_10      = (mkt.maturities > 6 & mkt.maturities <= 10)';
bumpMatrixFine = [mask_0_6, mask_6_10];

notionalsFine = VegaHedge(yearListVega, ratesSet, mkt, forward_list, B_grid, ...
                          delta, T_reset, X_pct_no_correction, bumpMatrixFine, bumpVega);

%% Exercise 1.f) Variation A - 3-cap hedge (3Y, 6Y, 10Y)

yearListVegaSwap = [3, 6, 10];
mask_0_3         = (mkt.maturities <= 3)';
mask_3_6         = (mkt.maturities > 3 & mkt.maturities <= 6)';
bumpMatrixSwap   = [mask_0_3, mask_3_6, mask_6_10];

notionalsSwap = VegaHedge(yearListVegaSwap, ratesSet, mkt, forward_list, B_grid, ...
                          delta, T_reset, X_pct_no_correction, bumpMatrixSwap, bumpVega);

%% Exercise 1.f) Variation B - Coarse-grained triangular bumps

t                = mkt.maturities(:);
mask_0_6_coarse  = max(0, min(1, (10 - t) / (10 - 6)));
mask_6_10_coarse = max(0, min(1, (t  - 6) / (10 - 6)));
bumpMatrixCoarse = [mask_0_6_coarse, mask_6_10_coarse];

notionalsCoarse = VegaHedge(yearListVega, ratesSet, mkt, forward_list, B_grid, ...
                            delta, T_reset, X_pct_no_correction, bumpMatrixCoarse, bumpVega);
