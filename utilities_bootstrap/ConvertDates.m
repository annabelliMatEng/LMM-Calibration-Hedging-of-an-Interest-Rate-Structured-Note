function [datesSet] = ConvertDates(dateObjects)
% CONVERTDATES Adjusts dates to business days using the Modified Following convention.
% 
% This function ensures dates are valid business days. It moves a non-business
% day to the next business day (Following), unless that day falls in the next 
% month. If so, it moves the date to the previous business day (Preceding).
%
% INPUT: 
%   dateObjects: A MATLAB datetime array.
% OUTPUT: 
%   datesSet:    A column vector of serial date numbers (datenum).

% 1. Input Validation
if ~isdatetime(dateObjects)
    error('InputError:NotDatetime', ...
        'The input must be a MATLAB datetime object or array.');
end

% 2. Identification and Adjustment of Business Days
% We use NaT to consider only standard weekends (Saturday/Sunday).
isHoliday = ~isbusday(dateObjects, NaT);

dateObjectsAdjusted = dateObjects;

if any(isHoliday)
    idxHolidays = find(isHoliday);
    for i = idxHolidays(:)'
        oldDate = dateObjects(i);
        
        % Step A: Try the 'Following' convention (next business day)
        newDate = busdate(oldDate, 1, NaT);
        
        % Step B: Check if the month has changed (Modified Following logic)
        if month(newDate) ~= month(oldDate)
            % If month changed, move back to the previous business day (Preceding)
            newDate = busdate(oldDate, -1, NaT);
        end
        
        dateObjectsAdjusted(i) = newDate;
        
    end
else
end

% 3. Conversion to Serial Numbers (datenum)
try
    % Convert the adjusted datetime objects to serial date numbers
    datesSet = datenum(dateObjectsAdjusted); 
    datesSet = datesSet(:); % Ensure output is a column vector
catch ME
    error('ConversionError: ProcessingFailed', ...
        'Error during conversion to serial dates: %s', ME.message);
end
end