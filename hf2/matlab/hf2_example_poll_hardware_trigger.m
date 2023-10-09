function sample_segments = hf2_example_poll_hardware_trigger(device_id, varargin)
% HF2_EXAMPLE_POLL_HARDWARE_TRIGGER Poll demodulator data in combination with a HW trigger
%
% USAGE SAMPLE_SEGMENTS = HF2_EXAMPLE_POLL_HARDWARE_TRIGGER(DEVICE_ID)
%
% Poll demodulator sample data from the device specified via DEVICE_ID using
% ziDAQServer's poll method in combination with a hardware trigger, ie, only
% send data to the PC when the DIO's 0th bit is high (configured via
% /devN/demods/M/trigger). DEVICE_ID should be a string, e.g., 'dev1000' or
% 'hf2-dev1000'.
%
% ziDAQServer's poll method allows the user to obtain ('poll') data he has
% subscribed to. Data can be obtained continuously in a loop. If asynchronous
% data recording is necessary please see example_record_async.m which uses the
% ziDAQRecord module.
%
% NOTE This example can only be ran on HF2 Instruments.
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% with a BNC cable.
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
isnonnegscalar = @(x) isnumeric(x) && isscalar(x) && (x > 0);
% The signal output mixer amplitude, [V].
p.addParamValue('amplitude', 0.1, @isnumeric);
% The number of DIO triggers we will manually issue and record demodulator
% sample segments for.
p.addParamValue('num_triggers', 10, isnonnegscalar);
p.parse(varargin{:});

%% More parameters relevant to this example.
out_c = '0'; % Signal output channel
% Get the value of the instrument's default Signal Output mixer channel.
out_mixer_c = num2str(ziGetDefaultSigoutMixerChannel(props, str2num(out_c)));
in_c = '0'; % Signal input channel
osc_c = '0'; % The oscillator to use.
demod_c = '0'; % demod channel, for paths on the device
demod_idx = str2double(demod_c)+1; % 1-based indexing, to access the data
demod_tc = 0.007; % [s]
demod_rate = 2e3; % [Samples/s]

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Configure the HF2 (assumes SigIn 0 connected to SigOut 0)
% Input settings
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/diff'], 0);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);

range = 1;
% Output settings
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/range'], range);
ziDAQ('setInt', ['/' device '/sigouts/*/enables/*'], 0);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c], 1);
ziDAQ('setDouble', ['/' device '/sigouts/*/amplitudes/*'], 0.000);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c], p.Results.amplitude);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/add'], 0);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);

% Oscillator settings
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], 1.5e6);

% Demodulator 0 settings
ziDAQ('setInt', ['/' device '/demods/' demod_c '/harmonic'], 1);
ziDAQ('setInt', ['/' device '/demods/' demod_c '/order'], 4);
ziDAQ('setInt', ['/' device '/demods/' demod_c '/oscselect'], str2double(osc_c));
ziDAQ('setDouble', ['/' device '/demods/' demod_c '/timeconstant'], demod_tc);
ziDAQ('setDouble', ['/' device '/demods/*/rate'], 0);
ziDAQ('setDouble', ['/' device '/demods/' demod_c '/rate'], demod_rate);
% Set the demods to record data when the DIO's zeroth bit is high
ziDAQ('setInt', ['/' device '/demods/' demod_c '/trigger'], 16);

% Configure DIO: to test this program
% Enable the DIO
ziDAQ('setInt', ['/' device '/dios/0/drive'], 1)
% Will will trigger when the zeroth bit is high
ziDAQ('setInt', ['/' device '/dios/0/output'], 0)

% Unsubscribe all streaming data
ziDAQ('unsubscribe', '*');

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device before issuing the
% ``poll`` command and clear the API's data buffers to remove any old data.
ziDAQ('sync');

% Subscribe to the demodulator.
ziDAQ('subscribe', ['/' device '/demods/' demod_c '/sample']);

% Poll command configuration.
poll_length = 0.1; % [s]
poll_timeout = 100; % [ms]
poll_flag = 0; % set to 0: disable the dataloss indicator (or data imbetween
% the polls will be filled with NaNs)

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Toggle DIO's 0th bit 'manually' here to test program
high_time = 0.1; % [s]
low_time = 0.5; % [s]
for i=1:p.Results.num_triggers
    pause(low_time);
    ziDAQ('setInt', ['/' device '/dios/0/output'], 1);
    % We should get demod data while the 0th bit is high
    pause(high_time);
    ziDAQ('setInt', ['/' device '/dios/0/output'], 0);
end
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Poll for data, it will return as much data as it can since the ``poll`` or ``sync``
data = ziDAQ('poll', poll_length, poll_timeout, poll_flag);

% Disable hardware trigger on all demods.
ziDAQ('setInt', ['/' device '/demods/*/trigger'], 0);

sample = data.(device).demods(demod_idx).sample;

% convert timestamps from ticks to seconds via the device's clockbase
% (the ADC's sampling rate), specify reference start time via t0.
clockbase = double(ziDAQ('getInt', ['/' device '/clockbase']));
t = (double(sample.timestamp) - double(sample.timestamp(1)))/clockbase;

% Calculate the magnitude
R = abs(sample.x + 1j*sample.y);

% This plots the data as its returned by ziDAQ('poll', ...), matlab will
% connect the signal segments with a line:
% figure(1);
% clf;
% plot(t, R);
% grid on;
% xlabel('t (s)');
% ylabel('R (V_{RMS})');

% Find the segments of the data based on changes in t, look for changes
% larger than twice demodulator's sampling rate. First get the real demod
% rate (it may differ from the one specified above due to rounding - demod
% rates can only be sub-multiples of 460KSamples/s).
demod_rate = ziDAQ('getDouble', ['/' device '/demods/' demod_c '/rate']);
dt = 1/demod_rate;
index = find(diff(t) > 2*dt) + 1;
% The data segments of interest are between start_index and
% stop_index. Assume that we start and stop at a region of interest (this
% won't necessary be the case if we're polling in a loop).
start_index = [1 index];
stop_index = [index-1 length(t)];

sample_segments = cell(1, length(start_index));

% Store the sample segments to a cell array
for i=1:length(start_index)
    indices = start_index(i):stop_index(i);
    % fields included with demod data
    sample_segments{i}.timestamp = sample.timestamp(indices);
    sample_segments{i}.x         = sample.x(indices);
    sample_segments{i}.y         = sample.y(indices);
    sample_segments{i}.frequency = sample.frequency(indices);
    sample_segments{i}.phase     = sample.phase(indices);
    % NOTE: 'bits' contains the values of the DIO. Since we're only recording data
    % when the 0th bit is high all(bitand(bits, 1)) should be true.
    sample_segments{i}.bits      = sample.bits(indices);
    sample_segments{i}.auxin0    = sample.auxin0(indices);
    sample_segments{i}.auxin1    = sample.auxin1(indices);
    % add some additional fields for convenience
    sample_segments{i}.t = t(indices);
    sample_segments{i}.R = R(indices);
end

figure(1);
clf; hold on; grid on;
% Plot the data segments separately to avoid the connecting line, this is
% slower.
for i=1:length(start_index)
    plot(sample_segments{i}.t, sample_segments{i}.R);
end
xlabel('t (s)');
ylabel('R (V_{RMS})');

end
