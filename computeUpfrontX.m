function [X_pct, NPV_fixed, NPV_coupons] = computeUpfrontX(spotVolMatrix, mktStrikes, forward_list, B_grid, delta, T_reset, digitalRiskFlag)
% COMPUTEUPFRONTX Calculates the upfront X% for the structured bond.
%
% INPUTS:
% spotVolMatrix : Matrix (80 x 13) of calibrated spot volatilities
% mktStrikes    : Vector of market strikes (used for spline interpolation)
% forward_list  : Quarterly forward rates L(Ti, Ti+1)
% B_grid        : Discount factors B(t0, Ti)
% delta         : Year fractions ACT/360 for Libor
% T_reset       : Year fractions ACT/365 to reset dates Ti
%
% OUTPUT:
% X_pct         : The upfront value in percentage (e.g., 0.02 for 2%)

numPeriods = 40; % 10 years, quarterly

%% Parameters retrieving
B = B_grid(2:end);

%% 1. Calculate NPV_fixed (Bank XX Pays: Euribor 3m + 2.00%)

NPV_fixed = 0;
for i = 1:numPeriods
    % Bank pays on the payment date B(i+1)
    NPV_fixed = NPV_fixed + B(i) * delta(i) * (forward_list(i) + 0.02);
end

%% 2. Calculate NPV_structured 
NPV_coupons = 0;

% Period 1: First Quarter Coupon is fixed at 4%
NPV_coupons = NPV_coupons + B(1) * delta(1) * 0.04;

% Periods 2 to 40: Structured Coupons
for i = 2:numPeriods
    % Determine bucket parameters (a, b, K) based on time

    timeInYears = T_reset(i-1);
    
    if timeInYears <= 3.0
        K = 0.0420; a = 0.010; b = 0.0450;
    elseif timeInYears <= 6.0
        K = 0.0470; a = 0.012; b = 0.0490;
    else
        K = 0.0540; a = 0.013; b = 0.0560;
    end
    
    % A.Interpolate the spot volatility for the current strike K
    sigma_row = spotVolMatrix(i-1, :);
    pp = spline(mktStrikes, sigma_row);
    sigma_K = ppval(pp, K);

    % B. Calculate Black components (Digital and Caplet)
    Li = forward_list(i);
    Ti = timeInYears;
    Bi_plus_1 = B(i);
    dlt = delta(i);
    
    d1 = (log(Li/K) + 0.5 * sigma_K^2 * Ti) / (sigma_K * sqrt(Ti));
    d2 = d1 - sigma_K * sqrt(Ti);
    
    % Digital Price (undiscounted) = N(d2)
    P_digital = dlt * Bi_plus_1 * normcdf(d2);
    
    % Caplet Price
    P_caplet = Bi_plus_1 * dlt * blkprice(Li, K, 0, Ti, sigma_K);

    % Digital risk correction (smile-adjusted)
    if digitalRiskFlag == 1
        dpp = fnder(pp, 1);
        dSigma_dK = ppval(dpp, K);
        Vega_caplet = Bi_plus_1 * dlt * blsvega(Li, K, 0, Ti, sigma_K);
        P_digital   = P_digital - dSigma_dK * Vega_caplet;
    end

    
    % C. Closed Formula
    
    coupon_NPV_i = dlt * Bi_plus_1 * (a + Li) ...
                   - (K + a - b) * P_digital ...
                   - P_caplet;
               
    NPV_coupons = NPV_coupons + coupon_NPV_i;
end

%% 3. Solve for X%
% NPV_fixed = X + NPV_coupons  =>  X = NPV_fixed - NPV_coupons
X_pct = NPV_fixed - NPV_coupons;

end