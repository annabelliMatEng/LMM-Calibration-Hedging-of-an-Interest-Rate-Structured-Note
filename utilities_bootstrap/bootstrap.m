function [dates, discounts, zeroRates] = bootstrap(datesSet, ratesSet)
% bootstrap: bootstraps the discount curve
%
% INPUTS: 
% datesSet:     struct containing dates: 
%               datesSet.settlement: contains the first settlment date
%               datesSet.depos: vector with deposit expiries 
%               datesSet.futures: 2-col matrix, containing future 
%               settle dates in the first column, future expiry dates 
%               in the second
%               datesSet.swaps: vector containing swaps expiries
% ratesSet:     struct containing rates: 
%               ratesSet.depos: matrix with bid-ask deposit rates
%               ratesSet.futures: matrix with bid-ask future rates
%               ratesSet.swaps: matrix with bid-ask swap rates
%
% OUTPUTS:
% dates: vector containing the expiry dates of the contracts
% discounts: vector containing the discount rates 
% zeroRates: vector containing the zero rates 

% Initialize settlment date
t0 = datesSet.settlement;
    
% Mid-price for Depos (bid/ask mean)
depoRates = mean(ratesSet.depos, 2);
% Dates for the Depos
depoDates = datesSet.depos;
% Mid-price for Futures
futRates = mean(ratesSet.futures, 2); 
%Dates for the Futures
futSettlementDates = datesSet.futures(:,1);
futExpiryDates = datesSet.futures(:,2);
    
% Mid-price for the Swaps 
swapRates = mean(ratesSet.swaps, 2);
%Dates for the Swaps
swapDates = datesSet.swaps;

% Initialize outputs
dates = t0;
discounts = 1;

% DEPOS   
% We search for the number of depos to use
start_futures = find(datesSet.depos > datesSet.futures(1,1), 1,'first');    
n_depo_to_use = start_futures -1;

% We compute the year fraction
delta_swap = yearfrac(t0,depoDates(1:n_depo_to_use),2);   

% We update the outputs
discounts = [discounts; 1 ./ (1 + depoRates(1:n_depo_to_use) .* delta_swap) ];   
dates = [dates; depoDates(1:n_depo_to_use)]; 

% FUTURES
% We search for the number of futures to use 
idx = futExpiryDates <= swapDates(2);
futSettlementDates = futSettlementDates(idx);  
futExpiryDates = futExpiryDates(idx);
futRates = futRates(idx);    
n_fut_to_use = length(futRates);

% We compute the year fraction
delta_fut = yearfrac(futSettlementDates, futExpiryDates, 2);

% We compute the forward discounts vector
df_forward = 1 ./ (1 + futRates .* delta_fut);

% We update the outputs
firstdf = discounts(end);
discounts = [discounts;firstdf * df_forward(1)];
dates=[dates; futExpiryDates(1)];
    
% We initialize zeroRates
zeroRates = -log(discounts(2:end))./yearfrac(t0,dates(2:end),3);

% For cycle to compute the discounts 
for i = 2:n_fut_to_use 
    % Two different cases: one for interpolation and one for extrapolation
        index = futSettlementDates(i)>futExpiryDates(i-1);  
    switch index     
        case 0
            ZR = interp1(dates(end-1:end),zeroRates(end-1:end),futSettlementDates(i),'linear');
            
        case 1     
            ZR = interp1(dates(end-1:end),zeroRates(end-1:end),futSettlementDates(i),'linear','extrap');  
    end 

    % Compute the discounts from the zero rates and update the outputs
    df = exp(- ZR * yearfrac(t0,futSettlementDates(i),3)); 
    discounts = [discounts; df * df_forward(i)];   
    dates = [dates;futExpiryDates(i)];    
    zeroRates = [zeroRates;-log(discounts(end))./yearfrac(t0,dates(end),3)];
     
end 

% SWAPS

% We search for the index corresponding to the first date greater than the
% expiry of the first Swap
idx = find(dates > swapDates(1), 1, 'first');

% We compute the first Swap's zero rate and discount factor
firstZR_swap = interp1(dates(idx-1:idx),zeroRates(idx-2:idx-1),swapDates(1),'linear');
firstdf_swap = exp(-firstZR_swap * yearfrac(dates(1),swapDates(1),3));

% We initialize the Basis Point Value
BPV = firstdf_swap * yearfrac(t0,swapDates(1),4);

% We initialize the discount factors for the swaps
df_swaps = [];
df_swaps(1) = firstdf_swap;

% For cycle to compute the discounts 
for i = 2:length(swapDates)
    % Discount factor of the i-th Swap
    df_swaps(i) = (1 - swapRates(i) * BPV) / (1 + swapRates(i) * yearfrac(swapDates(i-1), swapDates(i), 4));

    %We update the BPV
    BPV = BPV + yearfrac(swapDates(i-1), swapDates(i), 4) * df_swaps(i); 

    % We compute the zero rate 
    ZR_swap(i) = -log(df_swaps(i)) / (yearfrac(t0, swapDates(i), 3));

    % We update the outputs
    dates = [dates; swapDates(i)];
    discounts = [discounts; df_swaps(i)];
    zeroRates = [zeroRates; ZR_swap(i)];
end