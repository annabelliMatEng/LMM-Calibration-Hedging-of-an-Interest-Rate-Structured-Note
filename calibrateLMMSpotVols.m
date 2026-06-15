function spotVolStruct = calibrateLMMSpotVols(mkt, forward_list, B_grid, ...
                                               delta, T_reset, capPrices_mkt)
% CALIBRATELMMSPOTVOLS  Strips spot volatilities from cap prices via bucket bootstrapping.
%
% Convention:
%   - Pillar T_m is placed at the RESET of the LAST caplet of the T_m-cap,
%     i.e. T_pillar_m = T_reset(4*T_m - 1).
%   - 1Y bucket: spot vols = flat vol (no calibration, special case).
%   - Subsequent buckets: linear interpolation in reset time between
%     consecutive pillars; root-find the new pillar to match DeltaC.
%
% INPUTS:
%   mkt              : struct with .strikes, .maturities, .flatVol
%   forward_list     : forwards Libors
%   B_grid           : pay-date discount factors 
%   delta            : year fractions 
%   T_reset          : reset times aligned with caplet index
%   capPrices_mkt    : flat-vol cap prices, size [nMaturities x nStrikes]
%
% OUTPUT:
%   spotVolStruct    : struct with .spotVol [nCaplets x nStrikes],
%                      .pillarSigmas [nMaturities x nStrikes],
%                      .strikes, .maturities

    delta_new        = delta(2:end);
    forward_list_new = forward_list(2:end);
    B_grid_new       = B_grid(3:end); 


    nMaturities = length(mkt.maturities);
    nStrikes    = length(mkt.strikes);
    nCaplets    = 4 * mkt.maturities(end) - 1;

    spotVolMatrix = zeros(nCaplets, nStrikes);
    pillarMatrix  = zeros(nMaturities, nStrikes);

    for s = 1:nStrikes
        K = mkt.strikes(s);

        % ---------- 1Y bucket: trivial ----------
        flatVol_1Y         = mkt.flatVol(1, s);
        spotVolMatrix(1:3, s) = flatVol_1Y;
        pillarMatrix(1, s) = flatVol_1Y;

        T_pillar_prev      = T_reset(3);
        sigma_pillar_prev  = flatVol_1Y;
        idx_alpha          = 3;

        % ---------- Subsequent buckets ----------
        for m = 2:nMaturities
            idx_beta     = 4 * mkt.maturities(m) - 1;
            bucketIdx    = (idx_alpha + 1) : idx_beta;
            T_pillar_new = T_reset(idx_beta);

            % Target market DeltaC
            DeltaC = capPrices_mkt(m, s) - capPrices_mkt(m-1, s);

            % Objective: model bucket price minus market target
            objFun = @(sb) bucketPrice(sb, sigma_pillar_prev, T_pillar_prev, ...
                                       T_pillar_new, bucketIdx, ...
                                       forward_list_new, K, B_grid_new, ...
                                       delta_new, T_reset) - DeltaC;

            % Solve
            try
                sigma_pillar_new = fzero(objFun, [1e-4, 2.0]);
            catch ME
                warning('fzero failed at T=%dY, K=%.2f%%: %s. Using flat vol.', ...
                        mkt.maturities(m), K*100, ME.message);
                sigma_pillar_new = mkt.flatVol(m, s);
            end

            pillarMatrix(m, s) = sigma_pillar_new;

            % Fill spot vols in this bucket via linear interpolation
            for i = bucketIdx
                w = (T_reset(i) - T_pillar_prev) / (T_pillar_new - T_pillar_prev);
                spotVolMatrix(i, s) = sigma_pillar_prev + w * (sigma_pillar_new - sigma_pillar_prev);
            end

            % Update for next bucket
            T_pillar_prev     = T_pillar_new;
            sigma_pillar_prev = sigma_pillar_new;
            idx_alpha         = idx_beta;
        end
    end

    % Pack output
    spotVolStruct.spotVol       = spotVolMatrix;
    spotVolStruct.pillarSigmas  = pillarMatrix;
    spotVolStruct.strikes       = mkt.strikes;
    spotVolStruct.maturities    = mkt.maturities;
    spotVolStruct.T_reset       = T_reset;
end


% ============================================================
%  Helper: bucket price for a given candidate pillar vol
% ============================================================
function price = bucketPrice(sb, sa, Ta, Tb, bucketIdx, L, K, B, dlt, Tres)
    % Linear interpolation of spot vols
    sigmas = sa + (Tres(bucketIdx) - Ta) ./ (Tb - Ta) .* (sb - sa);

    % Black-76 caplet prices, vectorized
    [capletUndisc, ~] = blkprice(L(bucketIdx), K, 0, Tres(bucketIdx), sigmas);

    % Discount and sum
    price = sum(dlt(bucketIdx) .* B(bucketIdx) .* capletUndisc);
end