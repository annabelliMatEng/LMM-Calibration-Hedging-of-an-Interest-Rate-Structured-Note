function Notionals = VegaHedge(year_list, ratesSet, mkt, forward_list, B_grid, delta, T_reset, X0, bump_matrix, bump)
% AUTOMATEDVEGAHEDGE Calculates the required notionals of N hedging Caps to 
% neutralize the Vega bucket risks of a certificate.
%
% INPUTS:
% year_list        : Array of Cap maturities in years (e.g., [6, 10]). Sorted ascending.
% ratesSet         : Struct containing swap rates to retrieve ATM strikes.
% mkt              : Market struct containing flatVol, maturities, strikes.
% forward_list     : Forward rates array L(t_0, t_1...).
% B_grid           : Discount factors array B(t_0, t_0...).
% delta            : Year fractions.
% T_reset          : Reset times for the caplets.
% X0               : Baseline upfront value of the certificate.
% bump_matrix      : Matrix where each column 'i' is the bump vector for bucket 'i'.
%                    Rows must match the maximum number of caplets simulated.
% bump             : Scalar bump size used for the Vega denominator (e.g., 0.01).
%
% OUTPUTS:
% Notionals        : Vector containing the hedging notional weights for each Cap.

    % Ensure year_list is a column vector
    year_list = year_list(:);
    N = length(year_list);
    
    %% --- STEP 1: Compute Certificate Vegas ---
    % B_grid, delta, etc. are NOT aligned here yet, because the ComputeVega 
    % function handles the array alignment internally.
    vega_cert = zeros(N, 1);
    for i = 1:N
        % Extract the column corresponding to the i-th bucket
        current_bump_vector = bump_matrix(:, i);
        
        % Calculate the Certificate's Vega with respect to this specific bump
        vega_cert(i) = ComputeVega(bump, current_bump_vector, mkt, forward_list, B_grid, delta, T_reset, X0);
    end
    
    %% --- Align time indexes for Cap Pricing ---
    % Now we align the vectors for the local auxiliary function that prices the Caps
    B_grid_aligned = B_grid(2:end);       
    dlt_aligned = delta(2:end);           
    fwd_list_aligned = forward_list(2:end); 
    
    %% --- STEP 2: Setup Caps and Baseline Prices ---
    K_list = zeros(N, 1);
    numCaplets = zeros(N, 1);
    P_base = zeros(N, 1);
    vol_base = cell(N, 1); 
    
    for j = 1:N
        Y = year_list(j);
        numCaplets(j) = Y * 4 - 1; % Assuming quarterly payments
        
        K_list(j) = mean(ratesSet.swaps(Y)); 
        idx_Y = find(mkt.maturities == Y);
        
        % Spline interpolation of the baseline Flat Volatility
        flatVol_Y = interp1(mkt.strikes, mkt.flatVol(idx_Y, :), K_list(j), 'spline');
        vol_base{j} = ones(numCaplets(j), 1) * flatVol_Y;
        
        % Baseline price of the j-th Cap
        P_base(j) = priceAuxCap(numCaplets(j), K_list(j), vol_base{j}, fwd_list_aligned, B_grid_aligned, dlt_aligned, T_reset);
    end
    
    %% --- STEP 3: Build the Sensitivity Matrix A (Cap Vegas to Buckets) ---
    A = zeros(N, N);
    
    for j = 1:N % Columns: Hedging Instruments (Caps)
        for i = 1:N % Rows: Risk Factors (Buckets)
            
            % Determine the caplet index bounds that fall within Bucket i
            if i == 1
                start_idx = 1;
            else
                % Example: if previous year is 6, start_idx is 6 * 4 = 24
                start_idx = year_list(i-1) * 4; 
            end
            
            % Example: if current year is 6, end_idx is 6 * 4 - 1 = 23
            end_idx_bucket = year_list(i) * 4 - 1;
            
            % The actual end index must not exceed the Cap's total lifespan
            end_idx = min(end_idx_bucket, numCaplets(j));
            
            % Initialize the bumped volatility vector with the baseline
            vol_bumped = vol_base{j};
            
            % If the bucket's timeframe falls within the Cap's lifespan, apply the bump
            if start_idx <= end_idx
                % Apply the scalar bump EXACTLY to the caplets belonging to this bucket
                vol_bumped(start_idx : end_idx) = vol_bumped(start_idx : end_idx) + bump;
            end
            
            % Price the bumped Cap
            P_bumped = priceAuxCap(numCaplets(j), K_list(j), vol_bumped, fwd_list_aligned, B_grid_aligned, dlt_aligned, T_reset);
            
            % Calculate Vega sensitivity (Row i, Column j)
            A(i, j) = (P_bumped - P_base(j)) / bump;
        end
    end
    
    %% --- STEP 4 & 5: Solve the Hedging System ---
    % Set up the right-hand side vector (Certificate Vegas with opposite sign)
    b = -vega_cert;
    
    % Solve the linear system A * x = b using left matrix division
    Notionals = A \ b;
    
    %% --- Diagnostics ---
    fprintf('\n--- Automated Vega Hedging Results ---\n');
    for j = 1:N
        fprintf('%2dY Cap Notional Weight : %10.4f\n', year_list(j), Notionals(j));
    end
    fprintf('--------------------------------------\n');
    %% --- STEP 6: Visualization (Forward Curve vs Strikes) ---
    figure('Color', 'w', 'Name', 'Forward Curve & Strikes');
    hold on;
    grid on;

    % Ensure lengths match to avoid plotting errors
    plot_len = min(length(T_reset), length(fwd_list_aligned));
    T_plot = T_reset(1:plot_len);
    Fwd_plot = fwd_list_aligned(1:plot_len) * 100; % Convert to %

    % Plot Forward Curve
    plot(T_plot, Fwd_plot, '-o', 'LineWidth', 2, 'Color', [0, 0.447, 0.741], ...
         'MarkerFaceColor', [0.301, 0.745, 0.933], 'MarkerSize', 5, 'DisplayName', 'Forward Rates Curve');

    % Plot Swap Rate Strikes for each Cap
    color_map = lines(N); % Generate distinct colors for each strike
    for j = 1:N
        Y = year_list(j);
        K_pct = K_list(j) * 100; % Convert to %
        
        % Draw horizontal dashed line from t=0 up to Cap maturity
        plot([0, Y], [K_pct, K_pct], '--', 'LineWidth', 1.5, 'Color', color_map(j,:), ...
             'DisplayName', sprintf('Strike Cap %dY: %.2f%%', Y, K_pct));
             
        % Add a star marker exactly at maturity to show where the Cap ends
        plot(Y, K_pct, 'p', 'MarkerSize', 12, 'MarkerFaceColor', color_map(j,:), ...
             'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
    end

    % Plot Formatting
    xlabel('Time (Years)', 'Interpreter', 'latex', 'FontSize', 12);
    ylabel('Rate (\%)', 'Interpreter', 'latex', 'FontSize', 12);
    title('\textbf{Forward Curve vs Hedging Strikes}', 'Interpreter', 'latex', 'FontSize', 14);
    legend('Location', 'best', 'Interpreter', 'latex', 'FontSize', 10);
    set(gca, 'TickLabelInterpreter', 'latex');
    hold off;

end


%% --- Auxiliary Function: Cap Pricing ---
function price = priceAuxCap(numCaplets, K, vol_vector, L, B, dlt, T)
    % Prices a standard Cap by summing up its constituent caplets using Black's formula.
    
    price = 0;
    % Assuming standard array alignment where index 1 is the first future caplet
    for i = 1:numCaplets
        sigma = vol_vector(i);
        Li = L(i);
        Ti = T(i);
        
        % The caplet pays at T_{i+1}, so we discount with B(i+1)
        discount = B(i+1); 
        period_delta = dlt(i);
        
        % Calculate Black's price for the single caplet
        caplet_val = blkprice(Li, K, 0, Ti, sigma);
        
        % Accumulate discounted payoff
        price = price + (period_delta * discount * caplet_val);
    end
end