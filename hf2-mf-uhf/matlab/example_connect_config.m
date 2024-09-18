function r = example_connect_config(device_id, varargin)
% EXAMPLE_CONNECT_CONFIG Connect to and configure a Zurich Instruments device
%
% USAGE R = EXAMPLE_CONNECT_CONFIG(DEVICE_ID)
%
% Connect to the Zurich Instruments instrument specified by DEVICE_ID, obtain
% a single demodulator sample and calculate its RMS amplitude R. DEVICE_ID
% should be a string, e.g., 'dev1000' or 'uhf-dev1000'.
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% with a BNC cable.
%
% NOTE This is intended to be a simple example demonstrating how to connect
% to a Zurich Instruments device from ziPython. In most cases, data acquistion
% should use either ziDAQServer's poll() method or an instance of the
% ziDAQRecorder class.
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
% See also EXAMPLE_CONNECT, EXAMPLE_POLL.
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
  r = nan;
  fprintf('\nThis example requires lock-in functionality which is not available on %s.\n', device);
  return
end

% Define parameters relevant to this example. Default values specified by the
% inputParser are overwritten if specified via `varargin`.
p = inputParser;
% The signal output mixer amplitude, [V].
p.addParamValue('amplitude', 0.5, @isnumeric);
p.parse(varargin{:});
amplitude = p.Results.amplitude;

% Define some other helpful parameters.
demod_c = '0'; % demod channel
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
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1);
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
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], 400e3); % [Hz]

% Unsubscribe from any streaming data
ziDAQ('unsubscribe', '*');

% Pause to get a settled demodulator filter
pause(10*time_constant);

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device before issuing the
% ``getSample`` command. Note: ``sync`` must be issued after waiting for the
% demodulator filter to settle above.
ziDAQ('sync');

% Get a single demodulator sample. Note, `poll` or other higher-level
% functionality should almost always be be used instead of `getSample`.
sample = ziDAQ('getSample', ['/' device '/demods/0/sample']);
r = abs(sample.x + j*sample.y);
fprintf('Measured RMS amplitude: %fV.\n', r)

end
