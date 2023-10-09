function sample = example_poll(device_id, varargin)
% EXAMPLE_POLL Record demodulator data using ziDAQServer's synchronous poll function
%
% USAGE DATA = EXAMPLE_POLL(DEVICE_ID)
%
% Poll demodulator sample data from the device specified by DEVICE_ID using
% ziDAQServer's poll method. DEVICE_ID should be a string, e.g., 'dev1000' or
% 'uhf-dev1000'.
%
% ziDAQServer's poll method allows the user to obtain ('poll') demodulator
% data. Data can be obtained continuously in a loop. If asynchronous data
% recording is necessary please see example_record_async.m which uses the
% ziDAQRecord module.
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
           'e.g. ''dev1000'' or ''uhf-dev1000''.'])
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
apilevel_example = 6;
% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, apilevel_example);
ziApiServerVersionCheck();

branches = ziDAQ('listNodes', ['/' device ], 0);
if ~any(strcmpi([branches], 'DEMODS'))
  sample = [];
  fprintf('\nThis example requires lock-in functionality which is not available on %s.\n', device);
  return
end

%% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
p = inputParser;
isnonneg = @(x) isnumeric(x) && isscalar(x) && (x > 0);
% The length of time we'll record data (synchronously) in the first poll [s].
p.addParamValue('poll_duration', 1.0, isnonneg);
% The length of time to accumulate subscribed data (by sleeping) before polling a second time [s].
p.addParamValue('sleep_duration', 1.0, isnonneg);
% The signal output mixer amplitude, [V].
p.addParamValue('amplitude', 0.5, @isnumeric);
p.parse(varargin{:});
poll_duration = p.Results.poll_duration;
sleep_duration = p.Results.sleep_duration;
amplitude = p.Results.amplitude;

%% Define some other helper parameters.
demod_c = '0'; % Demod channel, 0-based indexing for paths on the device.
demod_idx = str2double(demod_c) + 1; % 1-based indexing, to access the data.
out_c = '0'; % signal output channel
% Get the value of the instrument's default Signal Output mixer channel.
out_mixer_c = num2str(ziGetDefaultSigoutMixerChannel(props, str2num(out_c)));
in_c = '0'; % signal input channel
osc_c = '0'; % oscillator
time_constant = 0.001; % [s]
demod_rate = 2e3;

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Configure the device ready for this experiment.
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 0);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 0);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2.0*amplitude);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/*'], 0);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c], amplitude);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c], 1);
if strfind(props.devicetype, 'HF2')
    ziDAQ('setInt', ['/' device '/sigins/' in_c '/diff'], 0);
    ziDAQ('setInt', ['/' device '/sigouts/' out_c '/add'], 0);
end
ziDAQ('setDouble', ['/' device '/demods/*/phaseshift'], 0);
ziDAQ('setInt', ['/' device '/demods/*/order'], 8);
ziDAQ('setDouble', ['/' device '/demods/' demod_c '/rate'], demod_rate);
ziDAQ('setInt', ['/' device '/demods/' demod_c '/harmonic'], 1);
ziDAQ('setInt', ['/' device '/demods/' demod_c '/enable'], 1);
ziDAQ('setInt', ['/' device '/demods/*/oscselect'], str2double(osc_c));
ziDAQ('setInt', ['/' device '/demods/*/adcselect'], str2double(in_c));
ziDAQ('setDouble', ['/' device '/demods/*/timeconstant'], time_constant);
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], 30e5); % [Hz]

% Unsubscribe all streaming data.
ziDAQ('unsubscribe', '*');

% Pause to get a settled lowpass filter.
pause(10*time_constant);

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device before issuing the
% ``poll`` command and clear the API's data buffers to remove any old
% data. Note: ``sync`` must be issued after waiting for the demodulator filter
% to settle above.
ziDAQ('sync');

% Subscribe to the demodulator sample.
ziDAQ('subscribe', ['/' device '/demods/' demod_c '/sample']);

% Poll data for poll_duration seconds.
poll_timeout = 500;
data = ziDAQ('poll', poll_duration, poll_timeout);

figure(1); clf;
grid on; box on; hold on;
if ziCheckPathInData(data, ['/' device '/demods/' demod_c '/sample']);
    sample = data.(device).demods(demod_idx).sample;
    t0 = sample.timestamp(1);
    plot_sample(sample, device, t0, 'b-');
else
    sample = [];
end

% Wait 2 seconds and poll data for 0.01 seconds.
% NOTE we get all the data from the buffer since the last poll command (much
% more data than 0.01 seconds)!
pause(sleep_duration);
poll_timeout = 0;
data2 = ziDAQ('poll', 0.01, poll_timeout);
if ziCheckPathInData(data2, ['/' device '/demods/' demod_c '/sample']);
    sample2 = data2.(device).demods(demod_idx).sample;
    if ~exist('t0', 'var')
        t0 = sample2.timestamp(1);
    end
    plot_sample(sample2, device, t0, 'k-');
    legend('poll 1', 'poll 2');
end

% Unsubscribe from all paths.
ziDAQ('unsubscribe', '*');

end

function plot_sample(sample, device, t0, style)
if sample.time.dataloss
    fprintf('Warning: Sample loss detected.');
end
r = sqrt(sample.x.^2 + sample.y.^2);
% convert timestamps from ticks to seconds via the device's clockbase
% (the ADC's sampling rate), specify reference start time via t0.
clockbase = double(ziDAQ('getInt', ['/' device '/clockbase']));
t = (double(sample.timestamp) - double(t0))/clockbase;
fprintf('Poll returned %.3f seconds of data\n', t(end)-t(1));
plot(t, r, style);
end
