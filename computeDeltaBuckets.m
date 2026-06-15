function deltaBuckets = computeDeltaBuckets(datesSet, ratesSet, mkt, spotVolMatrix, ...
    adj_caplet_dates, T_reset, X0, shockMode)
% COMPUTEDELTABUCKETS Computes DV01 sensitivities under different shock modes.
%
% Inputs:
% datesSet          - Market dates used in the bootstrap
% ratesSet          - Market rates used in the bootstrap
% mkt               - Market data structure
% spotVolMatrix     - Calibrated LMM spot volatility matrix
% adj_caplet_dates  - Adjusted quarterly dates of the structured bond
% T_reset           - Caplet reset times in years
% X0                - Base upfront computed with the original curve
% shockMode         - "single" for fine bucket DV01, "coarse" for coarse buckets
%
% Output:
% deltaBuckets      - Table with shifted upfronts and DV01s

notional = 50e6;
bp = 1e-4;

% Construct the table of the shocks
shockTable = buildRateShocks(datesSet, ratesSet, shockMode, bp);

% Reprice under each shock scenario
X_shifted = arrayfun(@(j) repriceWithShock(j, shockTable, datesSet, ratesSet, ...
    mkt, spotVolMatrix, adj_caplet_dates, T_reset), ...
    (1:height(shockTable))');

% Computation of the DV01
delta_X = X_shifted - X0;
DV01_EUR = -notional * delta_X;

% Final table
deltaBuckets = table(shockTable.bucketName, delta_X, DV01_EUR, 'VariableNames', {'bucketName', 'delta_X', 'DV01_EUR'});

end


%% AUXILIARY FUNCTIONS

function shockTable = buildRateShocks(datesSet, ratesSet, shockMode, bp)
% Builds rate shock scenarios for DV01 computation
%
% Inputs:
% datesSet   - Market dates used in the bootstrap
% ratesSet   - Market rates used in the bootstrap
% shockMode  - "single" for fine buckets, "coarse" for coarse-grained buckets
% bp         - Shock size (1 bp)
%
% Output:
% shockTable - Table containing shock names, reference dates and shock vectors

% Number of bootstrap instruments
nDepos = size(ratesSet.depos, 1);
nFut   = size(ratesSet.futures, 1);
nSwap  = size(ratesSet.swaps, 1);
nRates = nDepos + nFut + nSwap;

% Reference date of each market quote
rateDates = [datesSet.depos(:);
    datesSet.futures(:,2);
    datesSet.swaps(:)];

switch shockMode

    case "single"

        % +1bp shock for each individual bootstrap instrument
        bucketType = [repmat("Deposit", nDepos, 1);
            repmat("Future",  nFut,   1);
            repmat("Swap",    nSwap,  1)];

        bucketIndex = [(1:nDepos)';
            (1:nFut)';
            (1:nSwap)'];

        bucketName = bucketType + " " + string(bucketIndex);

        shockVector = bp * eye(nRates);

    case "coarse"
       
        % Coarse-grained shocks: 0-2y, 2-6y, 6-10y
        t = yearfrac(datesSet.settlement, rateDates, 3);

        w_0_2  = max(0, min(1, (6 - t) / (6 - 2)));

        w_2_6  = max(0, min((t - 2) / (6 - 2), ...
            (10 - t) / (10 - 6)));

        w_6_10 = max(0, min(1, (t - 6) / (10 - 6)));

        bucketName = ["0-2y"; "2-6y"; "6-10y"];

        % Each row is one shock scenario
        shockVector = bp * [w_0_2, w_2_6, w_6_10]';

    otherwise
        error("shockMode must be either 'single' or 'coarse'.");
end

% Final shock table
shockTable = table(bucketName, shockVector);

end


function X = repriceWithShock(j, shockTable, datesSet, ratesSet, mkt, spotVolMatrix, adj_caplet_dates, T_reset)
% Applies one rate shock scenario and reprices the product.
%
% Inputs:
% j                - Index of the shock scenario to apply
% shockTable       - Table containing the shock vectors
% datesSet         - Market dates used in the bootstrap
% ratesSet         - Market rates used in the bootstrap (not shocked)
% mkt              - Market data structure
% spotVolMatrix    - Calibrated LMM spot volatility matrix
% adj_caplet_dates - Adjusted quarterly dates of the structured bond
% T_reset          - Caplet reset times in years
%
% Output:
% X                - Fair upfront after applying the selected shock

% Extract the selected shock scenario
shockVector = shockTable.shockVector(j, :)';

% Number of bootstrap instruments by type
nDepos = size(ratesSet.depos, 1);
nFut   = size(ratesSet.futures, 1);
nSwap  = size(ratesSet.swaps, 1);

% Split the full shock vector into deposits, futures and swaps
shockDepos = shockVector(1:nDepos);
shockFut   = shockVector(nDepos+1:nDepos+nFut);
shockSwap  = shockVector(nDepos+nFut+1:nDepos+nFut+nSwap);

% Apply the shocks to the original bid/ask market quotes
shiftedRates = ratesSet;
shiftedRates.depos   = ratesSet.depos   + repmat(shockDepos, 1, size(ratesSet.depos, 2));
shiftedRates.futures = ratesSet.futures + repmat(shockFut,   1, size(ratesSet.futures, 2));
shiftedRates.swaps   = ratesSet.swaps   + repmat(shockSwap,  1, size(ratesSet.swaps, 2));

% Bootstrap the shifted curve
[curveDates, ~, zeroRates] = bootstrap(datesSet, shiftedRates);

% Recompute forward Libors and discount factors on the product schedule
[forward_list, delta, B_grid] = computeForwardLibors(datesSet.settlement, curveDates, zeroRates, adj_caplet_dates);

% Recompute the fair upfront under the shifted curve
X = computeUpfrontX(spotVolMatrix, mkt.strikes, forward_list, B_grid, delta, T_reset,0);

end