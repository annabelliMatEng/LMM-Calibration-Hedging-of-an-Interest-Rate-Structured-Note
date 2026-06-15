function [discount_factors] = fromdatetodiscount(t0,dates,zeroRates,target_dates)
% Computes discount factors for a set of future dates using linear interpolation of the zero rate curve.
%
% INPUTS
% t0            : valuation date 
% dates         : vector of dates corresponding to the zero rate curve
% zeroRates     : vector of zero rates
% target_dates  : vector of future dates for which the discount factors must be computed
%
% OUTPUT
% discount_factors : vector containing the discount factors corresponding to each date in 'coupon_dates'

% This function computes the discount factor for each coupon date by
% interpolating the zero rate curve and applying the standard exponential
% discounting formula.

% We add the first zero rate, corresponding to t0
zeroRates=[0;zeroRates];

discount_factors = [];
ZR = [];

for i = 1:length(target_dates)

    % We find the two surrounding dates 

    idx = find(dates > target_dates(i), 1, 'first');

    % A linear interpolation is performed between the two corresponding zero rates in
    % order to estimate the zero rate at the coupon date

    ZR(i) = interp1(dates(idx-1:idx),zeroRates(idx-1:idx),target_dates(i),'linear','extrap');

    % The interpolated zero rate is then used to compute the discount factor using continuous compounding

    discount_factors(i) = exp(-ZR(i)*yearfrac(t0,target_dates(i),3));
end

discount_factors = discount_factors'; % return column vector




