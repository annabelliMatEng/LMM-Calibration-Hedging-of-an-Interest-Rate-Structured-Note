function [dates, rates] = readExcelData(filename, formatData)
    % Leggiamo tutto il foglio come 'raw' per avere controllo totale
    [~, ~, raw] = xlsread(filename, 1);

    %% Funzione interna di utilità per il parsing delle date
    % Gestisce: stringhe, numeri seriali Excel e celle vuote
    function d = parseDate(val)
        if isempty(val) || (isnumeric(val) && isnan(val))
            d = NaN;
        elseif ischar(val) || isstring(val)
            % Se è testo, usa datenum con il formato specificato
            d = datenum(val, formatData);
        elseif isnumeric(val)
            % SE È UN NUMERO: Excel usa base 1900, MATLAB base 0000.
            % Il comando 'x2mdate' converte correttamente tra i due sistemi.
            d = x2mdate(val); 
        else
            d = NaN;
        end
    end

    %% Estrazione Date
    % Settlement (E8 -> riga 8, colonna 5)
    dates.settlement = parseDate(raw{8, 5});

    % Depositi (D11:D18 -> Righe 11-18, Colonna 4)
    dates.depos = cellfun(@parseDate, raw(11:18, 4));

    % Futures (Q12:R20 -> Colonne 17 e 18)
    dates.futures(:,1) = cellfun(@parseDate, raw(12:20, 17));
    dates.futures(:,2) = cellfun(@parseDate, raw(12:20, 18));

    % Swaps (D39:D88 -> Righe 39-88, Colonna 4)
    dates.swaps = cellfun(@parseDate, raw(39:88, 4));

    %% Estrazione Tassi (Rates)
    % Usiamo cell2mat per convertire i dati numerici dalle celle
    % Depos (E11:F18)
    rates.depos = cell2mat(raw(11:18, 5:6)) / 100;
    
    % Futures (E28:F36) -> Tasso = (100 - Prezzo)/100
    prezzi_futures = cell2mat(raw(28:36, 5:6));
    rates.futures = (100 - prezzi_futures) / 100;
    
    % Swaps (E39:F88)
    rates.swaps = cell2mat(raw(39:88, 5:6)) / 100;

end