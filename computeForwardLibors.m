function [forward_list, delta, B_grid] = computeForwardLibors(t0, dates, zeroRates, caplet_dates)
% Calculates a list of forward Libor rates.
%
% INPUTS:
% t0            : Valuation/Settlement date
% curve_dates   : Vector of dates from the bootstrapped curve (must start with t0)
% zeroRates     : Vector of zero rates from the bootstrapped curve
% caplet_dates  : Vector of quarterly grid dates (T0, T1, ..., Tn)
%
% OUTPUTS:
% forward_list  : Vector of forward rates L(t0, Ti, Ti+1)
% delta         : Year fractions (ACT/360) between Ti and Ti+1

% 1. Retrieve discount factors for all target dates using your function
% This returns B(t0, Ti) for every date in caplet_dates
B_grid = fromdatetodiscount(t0, dates, zeroRates, caplet_dates);


% 2. Calculate Forward Rates using the formula:
% L = (1/delta) * ( B(t0, Ti) / B(t0, Ti+1) - 1 )

% Year fractions ACT/360 for all periods at once
delta = yearfrac(caplet_dates(1:end-1), caplet_dates(2:end), 2);

% Forward rates for all periods at once
forward_list = (1 ./ delta) .* (B_grid(1:end-1) ./ B_grid(2:end) - 1);
end