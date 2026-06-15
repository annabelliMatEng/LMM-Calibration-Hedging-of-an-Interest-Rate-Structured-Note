function [hedgeNotionals, A, residualDV01] = DeltaHedge(year_list, datesSet, ratesSet, productDV01)
% Computes IRS notionals that hedge coarse-grained Delta risk.
%
% Inputs:
% year_list      - IRS maturities used for hedging
% datesSet       - Market dates used in the bootstrap
% ratesSet       - Market rates used in the bootstrap
% productDV01    - Coarse-grained DV01 vector of the structured product
%
% Outputs:
% hedgeNotionals - IRS hedge notionals
% A              - Matrix of coarse-grained IRS DV01s
% residualDV01   - Coarse-grained DV01 after hedging

bp = 1e-4;
year_list = year_list(:); %we want year_list to be a column vector
nSwaps = length(year_list);

% Base curve
[curveDates0, ~, zeroRates0] = bootstrap(datesSet, ratesSet);

% Coarse-grained shocks: 0-2y, 2-6y, 6-10y
shockTable = buildRateShocks(datesSet, ratesSet, "coarse", bp);

% Matrix of hedge swap DV01s
% Rows: coarse buckets
% Columns: hedge swaps
A = zeros(height(shockTable), nSwaps);
fixedRateList = zeros(nSwaps, 1);

settleDT = datetime(datesSet.settlement, 'ConvertFrom', 'datenum');

maturityDatesDT = datetime(year(settleDT) + year_list, month(settleDT), day(settleDT));

maturityDates = ConvertDates(maturityDatesDT);


for j = 1:nSwaps

    maturityDate = maturityDates(j);

    % ATM payer swap: fixed rate is the par swap rate
    [NPV0, fixedRate] = priceSwap(datesSet.settlement, maturityDate, curveDates0, zeroRates0, []);
    fixedRateList(j) = fixedRate;

    % Reprice the same swap under each coarse-grained shock
   NPV_shifted = zeros(height(shockTable), 1);

   for i = 1:height(shockTable)

        [curveDatesShifted, zeroRatesShifted] = bootstrapShiftedCurve(i, shockTable, datesSet, ratesSet);

        NPV_shifted(i) = priceSwap(datesSet.settlement, maturityDate, curveDatesShifted, zeroRatesShifted, fixedRate);

    end

    % DV01 per unit notional
    A(:, j) = NPV_shifted - NPV0;

end

% Solve productDV01 + A * hedgeNotionals = 0
hedgeNotionals = -A \ productDV01;

% Residual risk after hedge
residualDV01 = productDV01 + A * hedgeNotionals;

% Output table
hedgeTable = table(year_list, hedgeNotionals, ...
    'VariableNames', {'SwapMaturityYears', 'Notional_EUR'});

disp('Delta hedge notionals:')
disp(hedgeTable)

residualTable = table(shockTable.bucketName, residualDV01, ...
    'VariableNames', {'CoarseBucket', 'Residual_DV01_EUR'});

disp('Residual coarse-grained DV01 after hedge:')
disp(residualTable)

%% Visualization

figure('Color','w','Name','Delta Hedge Notionals');

bar(year_list, hedgeNotionals / 1e6, 0.55);
grid on;
yline(0, 'k-', 'LineWidth', 1);

xticks(year_list);
xticklabels(string(year_list) + "Y");

xlabel('IRS maturity (Years)', ...
    'Interpreter','latex', ...
    'FontSize', 13, ...
    'Color','k');

ylabel('Payer IRS notional (EUR mln)', ...
    'Interpreter','latex', ...
    'FontSize', 13, ...
    'Color','k');

title('\textbf{Delta hedge notionals}', ...
    'Interpreter','latex', ...
    'FontSize', 15, ...
    'Color','k');

for i = 1:length(year_list)

    if hedgeNotionals(i) < 0
        labelPosition = hedgeNotionals(i)/1e6 - 20;
        verticalAlignment = 'top';
    else
        labelPosition = hedgeNotionals(i)/1e6 + 20;
        verticalAlignment = 'bottom';
    end

    text(year_list(i), labelPosition, ...
        sprintf('%.1f mln', hedgeNotionals(i)/1e6), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment',verticalAlignment, ...
        'Interpreter','latex', ...
        'FontSize', 11, ...
        'Color','w', ...
        'FontWeight','bold');
end

subtitle('Negative payer notional corresponds to receiver IRS position', ...
    'Interpreter','latex', ...
    'Color','k', ...
    'FontSize', 11);

ax = gca;
ax.XColor = 'k';
ax.YColor = 'k';
ax.GridColor = [0.4 0.4 0.4];
ax.FontSize = 11;
ax.LineWidth = 1;
ax.TickLabelInterpreter = 'latex';
end


%% Auxiliary functions

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
        bucketDate = rateDates;

        shockVector = bp * eye(nRates);

    case "coarse"
       
        % Coarse-grained shocks: 0-2y, 2-6y, 6-10y
        t = yearfrac(datesSet.settlement, rateDates, 3);

        w_0_2  = max(0, min(1, (6 - t) / (6 - 2)));

        w_2_6  = max(0, min((t - 2) / (6 - 2), ...
            (10 - t) / (10 - 6)));

        w_6_10 = max(0, min(1, (t - 6) / (10 - 6)));

        bucketName = ["0-2y"; "2-6y"; "6-10y"];
        bucketDate = [datesSet.settlement; datesSet.settlement; datesSet.settlement];

        % Each row is one shock scenario
        shockVector = bp * [w_0_2, w_2_6, w_6_10]';

    otherwise
        error("shockMode must be either 'single' or 'coarse'.");
end

% Final shock table
shockTable = table(bucketName, bucketDate, shockVector);

end


function [NPV, fixedRate] = priceSwap(settlementDate, maturityDate, curveDates, zeroRates, fixedRate)
% Prices a spot-starting PAYER IRS per unit notional
%
% Inputs:
% settlementDate  - Swap start date
% maturityDate    - Swap maturity date
% curveDates      - Dates of the bootstrapped curve
% zeroRates       - Zero rates associated with curveDates
% fixedRate       - Fixed swap rate. If empty, the par swap rate is computed
%
% Outputs:
% NPV             - Payer IRS NPV per unit notional
% fixedRate       - Fixed rate used in the swap valuation

% Annual fixed-leg schedule, adjusted with the business day convention
settleDT = datetime(settlementDate, 'ConvertFrom', 'datenum');
maturityDT = datetime(maturityDate, 'ConvertFrom', 'datenum');

paymentDatesDT = datetime( ...
    (year(settleDT)+1 : year(maturityDT))', month(settleDT), day(settleDT));

paymentDates = ConvertDates(paymentDatesDT);

paymentDates(end) = maturityDate;

% Discount factors at fixed-leg payment dates
B = fromdatetodiscount(settlementDate, curveDates, zeroRates, paymentDates);

% Fixed-leg year fractions, 30/360 European convention
previousDates = [settlementDate; paymentDates(1:end-1)];
deltaFixed = yearfrac(previousDates, paymentDates, 6);

% Fixed-leg basis point value
BPV = sum(deltaFixed .* B);

% Floating leg value in a single-curve framework
floatLeg = 1 - B(end);

% If no fixed rate is provided, compute the ATM/par swap rate
if isempty(fixedRate)
    fixedRate = floatLeg / BPV;
end

% Fixed leg value
fixedLeg = fixedRate * BPV;

% Payer IRS: receive floating leg and pay fixed leg
NPV = floatLeg - fixedLeg;

end


function [curveDates, zeroRates] = bootstrapShiftedCurve(i, shockTable, datesSet, ratesSet)
% Applies one rate shock scenario and bootstraps the curve
%
% Inputs:
% i          - Index of the shock scenario to apply
% shockTable - Table containing the shock vectors
% datesSet   - Market dates used in the bootstrap
% ratesSet   - Original market rates used in the bootstrap
%
% Outputs:
% curveDates - Dates of the shifted bootstrapped curve
% zeroRates  - Zero rates of the shifted bootstrapped curve

% Extract the selected shock vector
shockVector = shockTable.shockVector(i, :)';

% Number of market instruments by type
nDepos = size(ratesSet.depos, 1);
nFut   = size(ratesSet.futures, 1);
nSwap  = size(ratesSet.swaps, 1);

% Split the shock vector into deposits, futures and swaps
shockDepos = shockVector(1:nDepos);
shockFut   = shockVector(nDepos+1:nDepos+nFut);
shockSwap  = shockVector(nDepos+nFut+1:nDepos+nFut+nSwap);

% Apply the shocks to the original bid/ask market quotes
shiftedRates = ratesSet;

shiftedRates.depos = ratesSet.depos + ...
    repmat(shockDepos, 1, size(ratesSet.depos, 2));

shiftedRates.futures = ratesSet.futures + ...
    repmat(shockFut, 1, size(ratesSet.futures, 2));

shiftedRates.swaps = ratesSet.swaps + ...
    repmat(shockSwap, 1, size(ratesSet.swaps, 2));

% Bootstrap the shifted curve
[curveDates, ~, zeroRates] = bootstrap(datesSet, shiftedRates);

end