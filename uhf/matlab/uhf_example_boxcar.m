function data = uhf_example_boxcar(device_id, varargin)
% UHF_EXAMPLE_BOXCAR Record boxcar data using ziDAQServer's synchronous poll function
%
% USAGE DATA = UHF_EXAMPLE_BOXCAR(DEVICE_ID)
%
% Poll boxcar data from the device specified by DEVICE_ID using ziDAQServer's
% blocking (synchronous) poll() method. DEVICE_ID should be a string, e.g.,
% 'dev1000' or 'uhf-dev1000'.
%
% ziDAQServer's poll method allows the user to obtain ('poll') data he has
% subscribed to. Data can be obtained continuously in a loop. If asynchronous
% data recording is necessary please see example_record_async.m which uses the
% ziDAQRecord module.
%
% NOTE This example can only be ran on UHF Instruments with the BOX option enabled.
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
required_err_msg = ['This example only runs with UHF Instruments with the ' ...
                    'Box Option enabled.'];
[device, props] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', 'UHF', ...
                                     'required_options', {'BOX'}, ...
                                     'required_err_msg', required_err_msg);
ziApiServerVersionCheck();

%% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
p = inputParser;
isnonnegscalar = @(x) isnumeric(x) && isscalar(x) && (x > 0);
% The signal output mixer amplitude, [V].
p.addParamValue('amplitude', 0.1, @isnumeric);
% The oscillator frequency of the generated signal [Hz].
p.addParamValue('frequency', 9.11e6, isnonnegscalar);
% The value of the boxcar's windowstart parameter [degrees].
p.addParamValue('windowstart', 75, isnonnegscalar);
% The value of the boxcar's windowsize parameter [seconds].
p.addParamValue('windowsize', 3e-9, isnonnegscalar);
p.parse(varargin{:});

%% More parameters relevant to this example.
boxcar_c = '0'; % boxcar channel, 0-based indexing for paths on the device
inputpwa_c = '0'; % inputpwa channel
boxcar_idx = str2double(boxcar_c) + 1; % 1-based indexing, to access the data
inputpwa_idx = str2double(inputpwa_c) + 1; % 1-based indexing, to access the data
out_c = '0';  % Signal output channel.
in_c = '0';  % Signal input channel.
osc_c = '0';  % Oscillator
out_mixer_c = num2str(ziGetDefaultSigoutMixerChannel(props, str2num(out_c)));

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

% configure the device ready for this experiment
periods_vals = pow2(2:12);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 0);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2*p.Results.amplitude);

ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/*'], 0);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c], p.Results.amplitude);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c], 1);

ziDAQ('setInt',    ['/' device '/inputpwas/' inputpwa_c '/oscselect'],   str2double(osc_c));
ziDAQ('setInt',    ['/' device '/inputpwas/' inputpwa_c '/inputselect'], str2double(in_c));
ziDAQ('setInt',    ['/' device '/inputpwas/' inputpwa_c '/mode'],        1);
ziDAQ('setDouble', ['/' device '/inputpwas/' inputpwa_c '/shift'],       0.0);
ziDAQ('setInt',    ['/' device '/inputpwas/' inputpwa_c '/harmonic'],    1);
ziDAQ('setInt',    ['/' device '/inputpwas/' inputpwa_c '/enable'],      1);

ziDAQ('setInt',    ['/' device '/boxcars/' boxcar_c '/oscselect'], str2double(osc_c));
ziDAQ('setInt',    ['/' device '/boxcars/' boxcar_c '/inputselect'], str2double(in_c));
ziDAQ('setDouble', ['/' device '/boxcars/' boxcar_c '/windowstart'], p.Results.windowstart);
ziDAQ('setDouble', ['/' device '/boxcars/' boxcar_c '/windowsize'], p.Results.windowsize);
ziDAQ('setDouble', ['/' device '/boxcars/' boxcar_c '/limitrate'], 1.0e3);
ziDAQ('setInt',    ['/' device '/boxcars/' boxcar_c '/periods'], periods_vals(1));
ziDAQ('setInt',    ['/' device '/boxcars/' boxcar_c '/enable'], 1);
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], p.Results.frequency); % [Hz]

% Unsubscribe all streaming data
ziDAQ('unsubscribe', '*'); pause(1.0);

% Wait for boxcar output to settle
pause(periods_vals(1)/p.Results.frequency)

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device before issuing the
% ``poll`` command and clear the API's data buffers to remove any old data.
ziDAQ('sync');

frequency_set = ziDAQ('getDouble', ['/' device '/oscs/' osc_c '/freq']);
windowstart_set = ziDAQ('getDouble', ['/' device '/boxcars/' boxcar_c '/windowstart']);
windowsize_set = ziDAQ('getDouble', ['/' device '/boxcars/' boxcar_c '/windowsize']);

% Subscribe to the boxcar sample and averaging periods and the inputpwa wave.
% We will see how the noise in the boxcar improves when increasing the number
% of averaging periods.
ziDAQ('subscribe', ['/' device '/boxcars/' boxcar_c '/sample']);
ziDAQ('subscribe', ['/' device '/boxcars/' boxcar_c '/periods']);
ziDAQ('subscribe', ['/' device '/inputpwas/' inputpwa_c '/wave']);
% We use getAsEvent() to ensure we obtain the first ``periods`` value; if its
% value didn't change, the server won't report the first value.
ziDAQ('getAsEvent', ['/' device '/boxcars/' boxcar_c '/periods']);

for i=1:length(periods_vals)
    pause(0.5)
    ziDAQ('setInt', ['/' device '/boxcars/' boxcar_c '/periods'], periods_vals(i));
end
poll_length = 0.1;
poll_timeout = 500;
data = ziDAQ('poll', poll_length, poll_timeout);

% unsubscribe from all paths
ziDAQ('unsubscribe', '*');

% check we go the data back we expect; this could only happen if we had a
% misconfiguration that caused the paths we subscribed to to not change, in
% which case poll doesn't return any values (unless getAsEvent is used, see
% above)
assert(isfield(data, device), 'Polled data is empty.');
assert(isfield(data.(device), 'boxcars'), 'data.(device) has no field ''boxcars''.');
assert(length(data.(device).boxcars) >= boxcar_idx, 'length(data.(device).boxcars) < boxcar_idx.')
assert(isfield(data.(device).boxcars, 'periods'), 'data.(device).boxcars has no field ''periods''.');
assert(isfield(data.(device).boxcars(boxcar_idx), 'sample'), 'data.(device).boxcars has no field ''sample''.');
assert(isfield(data.(device), 'inputpwas'), 'data.(device) has no field ''inputpwas''.');
assert(length(data.(device).inputpwas) >= inputpwa_idx, 'length(data.(device).inputpwas) < inputpwas_idx.')
assert(isfield(data.(device).inputpwas(inputpwa_idx), 'wave'), 'data.(device).inputpwas has no field ''wave''.');

boxcar_sample = data.(device).boxcars(boxcar_idx).sample;
boxcar_periods = data.(device).boxcars(boxcar_idx).periods;
pwa_wave = data.(device).inputpwas(inputpwa_idx).wave(end);


% When using API Level 4 poll() returns both the 'value' and 'timestamp'
% of the node. These are two vectors of the same length; which consist of
% (timestamp, value) pairs.
boxcar_value     = boxcar_sample.value;
boxcar_timestamp = boxcar_sample.timestamp;
boxcar_periods_value     = boxcar_periods.value;
boxcar_periods_timestamp = boxcar_periods.timestamp;

% Plot the output of the boxcar.
figure(1); clf;
grid on; box on; hold on;
% convert timestamps from ticks to seconds via clockbase
clockbase = double(ziDAQ('getInt', ['/' device '/clockbase']));
boxcar_t = (double(boxcar_timestamp) - double(boxcar_timestamp(1)))/clockbase;
boxcar_periods_t = (double(boxcar_periods_timestamp) - double(boxcar_timestamp(1)))/clockbase;
boxcar_periods_t = [boxcar_t(1), boxcar_periods_t, max(boxcar_t(end))];
boxcar_periods_value = [boxcar_periods_value(1), boxcar_periods_value boxcar_periods_value(end)];
ax = plotyy(boxcar_t, boxcar_value, boxcar_periods_t, boxcar_periods_value, 'plot', 'stairs');
xlabel('Time (s)');
xlim(ax(1), [0, min([boxcar_t(end); boxcar_periods_t(end)])])
xlim(ax(2), [0, min([boxcar_t(end); boxcar_periods_t(end)])])
set(get(ax(1), 'Ylabel'), 'String', 'Boxcar Value (V)');
set(get(ax(2), 'Ylabel'), 'String', 'No. Averaging Periods');
title(sprintf('\\bf The effect of averaging periods on the boxcar value.'))

% Plot the waveform from the inputpwa.
figure(2); clf;
grid on; box on; hold on;
pwa_wave.binphase = pwa_wave.binphase*360/(2*pi);
% The inputpwa waveform is stored in 'x', currently 'y' is unused.
windowsize_set_degrees = 360*frequency_set*windowsize_set;
phase_idx = (pwa_wave.binphase >= windowstart_set) & (pwa_wave.binphase <= windowstart_set + windowsize_set_degrees);
plot(pwa_wave.binphase, pwa_wave.x);
area(pwa_wave.binphase(phase_idx), pwa_wave.x(phase_idx));
plot(xlim, [0, 0], 'k-');
xlim([0, 360])
title(sprintf('\\bf Input PWA waveform, the shaded region shows the portion\n of the waveform that the boxcar is integrating.'))
xlabel('Phase (degrees)')
ylabel('Amplitude (V)')

end
