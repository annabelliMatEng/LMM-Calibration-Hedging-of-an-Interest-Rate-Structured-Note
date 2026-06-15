function Vega = ComputeVega(bump, buckets, mkt, forward_list, B_grid, delta, T_reset, X0)
% COMPUTEVEGA Computes the Vega of the structured product using the finite difference method (Bump-and-Revalue).
%
% INPUTS:
% bump              : The magnitude of the shift (e.g., 0.01 for a 1% parallel shift).
% buckets           : A matrix/vector of the same size as mkt.flatVol containing the shift coefficients (1 for parallel shift).
% mkt               : The original market structure containing flat volatilities.
% forward_list      : Forward rates array (L_i).
% B_grid            : Discount factors array (B_{i+1}).
% delta             : Year fractions.
% T_reset           : Reset times for the caplets.
% X0                : The baseline upfront value of the structured coupon leg (before the bump).
%
% OUTPUT:
% Vega              : The sensitivity of the structured leg's NPV to the applied shift in market flat volatility.
    


% 1. Market Data Bumping (Parallel Shift on Flat Vols)
mkt_bumped = mkt;
% Assuming flatVol is in absolute terms (e.g., 14.5 for 14.5%)
mkt_bumped.flatVol = mkt.flatVol + (bump .* buckets); 

% If your market struct also uses a percentage representation
if isfield(mkt, 'flatVolPct')
    mkt_bumped.flatVolPct = mkt.flatVolPct + ((bump .* buckets) * 100);
end

% 2. Market Re-Calibration 
% Recompute Flat Cap Prices using bumped volatilities
capPrices_mkt_bumped = computeCapPricesFlat(mkt_bumped, forward_list, B_grid, delta, T_reset);

% Re-bootstrap the LMM Spot Volatility matrix based on bumped cap prices
spotVolStruct_bumped = calibrateLMMSpotVols(mkt_bumped, forward_list, B_grid, delta, T_reset, capPrices_mkt_bumped);
matrix_bumped = spotVolStruct_bumped.spotVol;

% 3. Instrument Re-Pricing (Calling your computeUpfrontX function)
% We pass the bumped spot volatility matrix to evaluate the new MTM of the product.
[Xnew, ~, ~] = computeUpfrontX(matrix_bumped, mkt_bumped.strikes, forward_list, B_grid, delta, T_reset, 0);

% 4. Vega Calculation
% Vega is the finite difference of the NPV of the option-embedded leg divided by the bump magnitude.
Vega = -(Xnew - X0) / bump;

end