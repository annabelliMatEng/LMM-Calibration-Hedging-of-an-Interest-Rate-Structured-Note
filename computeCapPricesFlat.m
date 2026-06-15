function capPrices_flat = computeCapPricesFlat(mkt, forwardRates, df_pay, delta, T_reset)
% Computes the market price of Caps using the flat vol table.
%
% INPUTS:
% mkt          : Structure containing .strikes and .maturities (1xM and 1xN)
%                and .flatVol matrix (nMaturities x nStrikes)
% forwardRates : Vector of forward Libor rates L(t0, Ti, Ti+1)
% df_pay       : Vector of discount factors B(t0, Ti+1) for payment dates
% delta        : Vector of year fractions (ACT/360) for Libor periods
% T_reset      : Vector of year fractions (ACT/365) from t0 to reset dates Ti
%
% OUTPUT:
% capPrices_flat : Matrix [nMaturities x nStrikes] of Cap prices

%% Parameters setting 
df_pay = df_pay(3:end); 
delta = delta(2:end);
forwardRates = forwardRates(2:end);
%%
nMaturities = length(mkt.maturities);
nStrikes    = length(mkt.strikes);
capPrices_flat = zeros(nMaturities, nStrikes);

% Loop over each maturity pillar
for m = 1:nMaturities
    numCaplets = (4 * mkt.maturities(m)) - 1;

    % Slice the relevant caplet data once per maturity
    F_vec     = forwardRates(1:numCaplets);
    T_vec     = T_reset(1:numCaplets);
    df_vec    = df_pay(1:numCaplets);
    delta_vec = delta(1:numCaplets);

    % Loop over each strike pillar
    for s = 1:nStrikes
        K    = mkt.strikes(s);
        sigF = mkt.flatVol(m, s);

        % Vectorized Black prices across all caplets at once
        [undiscountedCaplets, ~] = blkprice(F_vec, K, 0, T_vec, sigF);

        % Vectorized caplet summation
        capPrices_flat(m, s) = sum(delta_vec .* df_vec .* undiscountedCaplets);
    end
end
end