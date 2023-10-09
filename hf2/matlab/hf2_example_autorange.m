function sigin_range_auto = hf2_example_autorange(device_id, varargin)
% HF2_EXAMPLE_AUTORANGE set an appropriate range for a Signal Input channel
%
% SIGIN_RANGE = HF2_EXAMPLE_AUTORANGE(DEVICE_ID)
%
% Find and set a suitable value SIGIN_RANGE for a signal input channel range
% based on the values of the /devX/status/adc{0, 1}min and
% /devX/status/min/adc{0, 1}max nodes. DEVICE_ID specifies the HF2 device
% (DEVICE_ID should be a string, e.g., 'dev1000' or 'hf2-dev1000').
%
% Returns:
%
%   sigin_range_auto (double): the value of the signal input range as
%   determined by the example. The value actually set on the device is best
%   obtained via: ziDAQ('getDouble', ['/' device '/sigins/' channel '/range'])
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% with a BNC cable.
%
% NOTE This example can only be ran on HF2 Instruments.
%
% NOTE Please ensure that the ziDAQ folders 'Driver' and 'Utils' are in your
% Matlab path. To do this (temporarily) for one Matlab session please navigate
% to the ziDAQ base folder containing the 'Driver', 'Examples' and 'Utils'
% subfolders and run the Matlab function ziAddPath().
% >>> ziAddPath;
%
% Use either of the commands:
% >>> help ziDAQ
% >>> doc ziDAQ
% in the Matlab command window to obtain help on all available ziDAQ commands.
%
% Copyright 2008-2018 Zurich Instruments AG

clear ziDAQ;

if ~exist('device_id', 'var')
    error(['No value for device_id specified. The first argument to the ' ...
           'example should be the device ID on which to run the example, ' ...
           'e.g. ''dev1000'' or ''hf2-dev1000''.'])
end

% Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
if ~(exist('ziDAQ') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
    fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
    fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
    fprintf('This can be found in the API subfolder of your LabOne installation.\n');
    fprintf('On Windows this is typically:\n');
    fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
    return
end

% The API level supported by this example.
apilevel_example = 1;
% Create an API session; connect to the correct Data Server for the device.
required_err_msg = 'This example only runs with HF2 Instruments.';
[device, props] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', 'HF2', ...
                                     'required_options', {}, ...
                                     'required_err_msg', required_err_msg);
ziApiServerVersionCheck();

%% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
p = inputParser;
input_channels = [0, 1];
is_input_channel = @(x) assert(ismember(x, input_channels), ...
                               'Invalid value for input_channel: %d. Valid values: %s.', x, mat2str(input_channels));
% The Signal Input channel to use.
p.addParamValue('input_channel', 0, is_input_channel);
p.parse(varargin{:});

input_channel = p.Results.input_channel;

%% Define some other helper variables.
% The /devX/status/adc{0, 1}min and /devX/status/min/adc{0, 1}max nodes take
% values between -127 and 127
adc_min = -127;
adc_max = 127;
adc_minmax_scaling = 1.0 / 127.0;
% Maximum signal input range on the HF2
max_sigin_range = 2;
% Time to sleep before re-checking adcmin/adcmax values
time_to_sleep = 0.015;

for i=0:4
    sigin_range = ziDAQ('getDouble', sprintf('/%s/sigins/%d/range', device, input_channel));
    min_value = ziDAQ('getDouble', sprintf('/%s/status/adc%dmin', device, input_channel));
    max_value = ziDAQ('getDouble', sprintf('/%s/status/adc%dmax', device, input_channel));
    if (max_value >= adc_max) || (min_value <= adc_min)
        ziDAQ('setDouble', sprintf('/%s/sigins/%d/range', device, input_channel), max_sigin_range);
        sigin_range_auto = max_sigin_range;
    else
        scaling = max(abs([min_value, max_value]))*1.5*adc_minmax_scaling;
        % Avoid a range of 0
        sigin_range_auto = max([sigin_range*scaling, 1e-6]);
        ziDAQ('setDouble', sprintf('/%s/sigins/%d/range', device, input_channel), sigin_range_auto)
        ziDAQ('sync');
    end
    pause(time_to_sleep);
end

end
